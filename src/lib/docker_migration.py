"""Export and verify Docker migration bundles; callers must freeze all host writers."""
import argparse
import contextlib
import hashlib
import ipaddress
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

OWNER = 'fusionbox-docker-migration-v1'
FORMAT = 1
MANIFEST = 'manifest.json'
DECLARATION = 'declaration.json'
NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}')
LOGICAL = re.compile(r'[a-z0-9][a-z0-9_-]{0,47}')
JOURNAL_OWNER = 'fusionbox-docker-restore-v1'
JOURNAL_BASE = Path('/var/lib/fusionbox/docker-migration')
TX = re.compile(r'[a-f0-9]{32}')
TRANSACTION_LABEL = 'fusionbox.restore.transaction'
BIND_MARKER = '.fusionbox-restore-owner'


def docker(*args, stdout=None):
    if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'):
        raise ValueError('Remote or alternate Docker daemons are unsupported')
    result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', *args],
                            stdout=stdout or subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise RuntimeError('Docker operation failed (output withheld to protect secrets)')
    return b'' if stdout is not None else result.stdout


def js(*args):
    return json.loads(docker(*args))


def digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(block)
    return value.hexdigest()


def no_symlink_ancestors(path, allow_missing=False):
    path = Path(path).absolute()
    for candidate in (path, *path.parents):
        try:
            if stat.S_ISLNK(candidate.lstat().st_mode):
                raise ValueError('Symlink source or ancestor unsupported: ' + str(path))
        except FileNotFoundError:
            if allow_missing:
                continue
            raise ValueError('Source path unavailable: ' + str(path)) from None


def _norm_arch(value):
    """docker info reports x86_64/aarch64 while image inspect reports amd64/arm64."""
    return {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(value, value)


def daemon_info():
    info = js('info', '--format', '{{json .}}')
    security = [str(item).lower() for item in info.get('SecurityOptions') or []]
    if info.get('DockerRootDir') is None or any('rootless' in item for item in security):
        raise ValueError('Rootless or unidentified Docker daemon unsupported')
    root = Path(info['DockerRootDir']).resolve()
    no_symlink_ancestors(root)
    return info, root


def select(container_names, project):
    if bool(container_names) == bool(project):
        raise ValueError('Select containers or one complete Compose project')
    if project:
        if not NAME.fullmatch(project):
            raise ValueError('Invalid Compose project name')
        ids = docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).decode().split()
        if not ids:
            raise ValueError('Compose project has no containers')
        containers = js('inspect', *ids)
        config_files = {str((item.get('Config', {}).get('Labels') or {}).get('com.docker.compose.project.config_files', ''))
                        for item in containers}
        working_dirs = {str((item.get('Config', {}).get('Labels') or {}).get('com.docker.compose.project.working_dir', ''))
                        for item in containers}
        if len(config_files) != 1 or not next(iter(config_files)) or len(working_dirs) != 1:
            raise ValueError('Compose project configuration identity unavailable or inconsistent')
        compose_files = next(iter(config_files)).split(',')
        if any(not Path(path).is_absolute() or not Path(path).is_file() for path in compose_files):
            raise ValueError('Compose project configuration files unavailable')
        command = ['compose', '-p', project]
        for path in compose_files:
            command.extend(('-f', path))
        rendered = js(*command, 'config', '--format', 'json')
        expected_services = set((rendered.get('services') or {}).keys())
        actual_services = {(item.get('Config', {}).get('Labels') or {}).get('com.docker.compose.service')
                           for item in containers}
        if not expected_services or actual_services != expected_services:
            raise ValueError('Compose project is not fully created; missing or unknown services')
        if any((item.get('Config', {}).get('Labels') or {}).get('com.docker.compose.project') != project
               for item in containers):
            raise ValueError('Incomplete Compose project selection')
        if any((item.get('Config', {}).get('Labels') or {}).get('com.docker.compose.oneoff', 'False').lower() == 'true'
               for item in containers):
            raise ValueError('Compose one-off containers unsupported')
        return containers, {'kind': 'compose-project', 'project': project}
    if not container_names or len(container_names) != len(set(container_names)):
        raise ValueError('Container selection must be nonempty and unique')
    if any(not NAME.fullmatch(name) for name in container_names):
        raise ValueError('Invalid container name or ID')
    containers = js('inspect', *container_names)
    if len(containers) != len(container_names) or len({c['Id'] for c in containers}) != len(container_names):
        raise ValueError('Container selection did not resolve uniquely')
    return containers, {'kind': 'containers', 'requested': container_names}


def reject_unsupported(container):
    host = container.get('HostConfig') or {}
    state = container.get('State') or {}
    config = container.get('Config') or {}
    if host.get('Privileged'):
        raise ValueError('Privileged containers unsupported')
    if host.get('CgroupnsMode') == 'host' or host.get('UsernsMode') == 'host':
        raise ValueError('Host cgroup or user namespace modes unsupported')
    if host.get('Devices') or host.get('DeviceRequests'):
        raise ValueError('Device mappings unsupported')
    if host.get('Tmpfs') or config.get('Volumes') and any(m.get('Type') == 'tmpfs' for m in container.get('Mounts', [])):
        raise ValueError('tmpfs mounts unsupported')
    if host.get('PidMode') == 'host' or host.get('IpcMode') == 'host':
        raise ValueError('Host PID or IPC namespaces unsupported')
    if str(host.get('NetworkMode', '')).startswith('container:'):
        raise ValueError('Container-shared network namespaces unsupported')
    if host.get('AutoRemove') or state.get('Paused') or state.get('Restarting'):
        raise ValueError('Auto-remove, paused, or restarting containers unsupported')
    unsupported = {
        'Links': host.get('Links'), 'VolumesFrom': host.get('VolumesFrom'),
        'DeviceCgroupRules': host.get('DeviceCgroupRules'), 'BlkioWeightDevice': host.get('BlkioWeightDevice'),
        'BlkioDeviceReadBps': host.get('BlkioDeviceReadBps'), 'BlkioDeviceWriteBps': host.get('BlkioDeviceWriteBps'),
        'BlkioDeviceReadIOps': host.get('BlkioDeviceReadIOps'), 'BlkioDeviceWriteIOps': host.get('BlkioDeviceWriteIOps'),
        'StorageOpt': host.get('StorageOpt'), 'CgroupParent': host.get('CgroupParent'),
    }
    if any(value for value in unsupported.values()):
        names = ', '.join(sorted(key for key, value in unsupported.items() if value))
        raise ValueError('Container fields cannot be restored losslessly: ' + names)
    if host.get('NetworkMode') == 'host':
        raise ValueError('Host network mode unsupported')
    if config.get('OnBuild') or config.get('Shell'):
        raise ValueError('Image build-only container fields unsupported')
    if isinstance(config.get('Entrypoint'), list) and len(config['Entrypoint']) > 1:
        raise ValueError('Multi-element entrypoint cannot be restored losslessly by this implementation')
    health = config.get('Healthcheck') or {}
    test = health.get('Test') or []
    if test and (not isinstance(test, list) or test[0] not in ('NONE', 'CMD-SHELL') or len(test) > 2):
        raise ValueError('Only NONE or one CMD-SHELL healthcheck can be restored losslessly')
    for endpoint in (container.get('NetworkSettings', {}).get('Networks') or {}).values():
        if endpoint.get('Links') or endpoint.get('DriverOpts'):
            raise ValueError('Network endpoint links or driver options unsupported')
    for mount in container.get('Mounts') or []:
        if mount.get('Type') in ('cluster', 'secret', 'config', 'tmpfs', 'npipe'):
            raise ValueError('Secret, config, tmpfs, or nonlocal mounts unsupported')


def parse_binds(values, confirmations):
    result = {}
    confirmed = set(confirmations)
    for value in values:
        if '=' not in value:
            raise ValueError('Bind mapping must be ABSOLUTE_SOURCE=logical_name')
        source, logical = value.rsplit('=', 1)
        path = Path(source)
        if not path.is_absolute() or not LOGICAL.fullmatch(logical):
            raise ValueError('Invalid bind source or logical name')
        canonical = str(path.resolve())
        if canonical != source or source not in confirmed:
            raise ValueError('Each canonical bind source needs matching --confirm-bind')
        if canonical in result or logical in result.values():
            raise ValueError('Duplicate bind source or logical name')
        result[canonical] = logical
    if confirmed != set(result):
        raise ValueError('--confirm-bind must exactly match mapped bind sources')
    return result


def overlap(left, right):
    left, right = Path(left), Path(right)
    return left == right or left in right.parents or right in left.parents


def audit_tree(path):
    path = Path(path)
    no_symlink_ancestors(path)
    info = path.lstat()
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
        raise ValueError('Special source unsupported: ' + str(path))
    device = info.st_dev
    if stat.S_ISREG(info.st_mode):
        return
    for current, directories, files in os.walk(path, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            child = Path(current) / name
            child_info = child.lstat()
            if stat.S_ISLNK(child_info.st_mode):
                raise ValueError('Symlink in source tree unsupported: ' + str(child))
            if child_info.st_dev != device:
                raise ValueError('Filesystem boundary in source tree unsupported: ' + str(child))
            if not (stat.S_ISREG(child_info.st_mode) or stat.S_ISDIR(child_info.st_mode)):
                raise ValueError('Special file in source tree unsupported: ' + str(child))


def image_declaration(container):
    image = js('image', 'inspect', container['Image'])[0]
    return {
        'id': image['Id'], 'repo_digests': image.get('RepoDigests') or [], 'repo_tags': image.get('RepoTags') or [],
        'architecture': image.get('Architecture'), 'os': image.get('Os'),
        'variant': image.get('Variant'),
    }


def container_declaration(container):
    config, host = container.get('Config') or {}, container.get('HostConfig') or {}
    networks = {}
    for name, endpoint in sorted((container.get('NetworkSettings', {}).get('Networks') or {}).items()):
        networks[name] = {
            'aliases': endpoint.get('Aliases') or [], 'ip_address': endpoint.get('IPAddress') or '',
            'global_ipv6_address': endpoint.get('GlobalIPv6Address') or '',
            'ip_prefix_len': endpoint.get('IPPrefixLen'),
            'global_ipv6_prefix_len': endpoint.get('GlobalIPv6PrefixLen'),
            # Audit only, like ip_address: engine-assigned MACs are per-endpoint on
            # every real container; a user-pinned MAC travels through create.mac_address.
            'mac_address': endpoint.get('MacAddress') or '',
        }
    return {
        'id': container['Id'], 'name': container.get('Name', '').lstrip('/'), 'created': container.get('Created'),
        'image_reference': config.get('Image'), 'image_id': container['Image'],
        'environment': config.get('Env') or [], 'entrypoint': config.get('Entrypoint'), 'cmd': config.get('Cmd'),
        'user': config.get('User') or '', 'working_dir': config.get('WorkingDir') or '',
        'restart_policy': host.get('RestartPolicy') or {}, 'healthcheck': config.get('Healthcheck'),
        'ports': host.get('PortBindings') or {},
        'exposed_ports': config.get('ExposedPorts') or {},
        'resources': {key: host.get(key) for key in (
            'Memory', 'MemoryReservation', 'MemorySwap', 'MemorySwappiness', 'NanoCpus', 'CpuShares',
            'CpuPeriod', 'CpuQuota', 'CpusetCpus', 'CpusetMems', 'PidsLimit', 'OomKillDisable', 'ShmSize')},
        'network_mode': host.get('NetworkMode'),
        'primary_network': (host.get('NetworkMode') if host.get('NetworkMode') not in ('default', '') else 'bridge'),
        'networks': networks,
        'labels': config.get('Labels') or {},
        'create': {
            'hostname': config.get('Hostname') or '', 'domainname': config.get('Domainname') or '',
            'mac_address': config.get('MacAddress') or '', 'attach_stdin': bool(config.get('AttachStdin')),
            'attach_stdout': bool(config.get('AttachStdout', True)), 'attach_stderr': bool(config.get('AttachStderr', True)),
            'open_stdin': bool(config.get('OpenStdin')), 'stdin_once': bool(config.get('StdinOnce')),
            'tty': bool(config.get('Tty')), 'stop_signal': config.get('StopSignal') or '',
            'stop_timeout': config.get('StopTimeout'), 'readonly_rootfs': bool(host.get('ReadonlyRootfs')),
            'cap_add': host.get('CapAdd') or [], 'cap_drop': host.get('CapDrop') or [],
            'dns': host.get('Dns') or [], 'dns_options': host.get('DnsOptions') or [],
            'dns_search': host.get('DnsSearch') or [], 'extra_hosts': host.get('ExtraHosts') or [],
            'group_add': host.get('GroupAdd') or [], 'security_opt': host.get('SecurityOpt') or [],
            'sysctls': host.get('Sysctls') or {}, 'ulimits': host.get('Ulimits') or [],
            'log_config': host.get('LogConfig') or {}, 'runtime': host.get('Runtime') or '',
            'init': host.get('Init'), 'oom_score_adj': host.get('OomScoreAdj') or 0,
        },
        'mounts': [{key: mount.get(key) for key in ('Type', 'Name', 'Source', 'Destination', 'Driver', 'Mode', 'RW', 'Propagation')}
                   for mount in container.get('Mounts') or []],
        # MaskedPaths/ReadonlyPaths are engine-managed isolation metadata: every
        # container gets engine defaults (including host-specific entries such as
        # /sys/devices/virtual/block/dm-*, which differ across hosts by design).
        # There is no CLI flag to set them, so they can never carry user intent
        # through `docker run`; they are recorded here for audit only, and the
        # target engine applies its own (never fewer by default) at create time.
        # Treating them as unsupported made every real `docker run` container
        # unexportable — found by the first real-machine acceptance run.
        'masked_paths': host.get('MaskedPaths') or [],
        'readonly_paths': host.get('ReadonlyPaths') or [],
        'original_running': bool(container.get('State', {}).get('Running')),
    }


def assert_no_external_writers(selected_ids, sources):
    all_ids = docker('ps', '-aq').decode().split()
    all_containers = js('inspect', *all_ids) if all_ids else []
    for other in all_containers:
        if other['Id'] in selected_ids:
            continue
        for mount in other.get('Mounts') or []:
            if mount.get('RW') and mount.get('Source') and any(overlap(mount['Source'], path) for path in sources):
                raise ValueError('Selected data has a writer outside the stopped container set')


def prepare(container_names, project, bind_values, confirmations):
    info, docker_root = daemon_info()
    containers, selection = select(container_names, project)
    selected_ids = {item['Id'] for item in containers}
    binds = parse_binds(bind_values, confirmations)
    volumes, sources = {}, []
    all_ids = docker('ps', '-aq').decode().split()
    all_containers = js('inspect', *all_ids) if all_ids else []
    for container in containers:
        reject_unsupported(container)
        for mount in container.get('Mounts') or []:
            kind, source = mount.get('Type'), mount.get('Source')
            if kind == 'volume':
                name = mount.get('Name')
                if not name or not NAME.fullmatch(name):
                    raise ValueError('Invalid volume identity')
                volume = js('volume', 'inspect', name)[0]
                if volume.get('Driver') != 'local' or volume.get('Options'):
                    raise ValueError('Only local filesystem Docker volumes are supported')
                path = Path(volume['Mountpoint']).resolve()
                if path != docker_root / 'volumes' / name / '_data':
                    raise ValueError('Unexpected local volume mountpoint')
                volumes[name] = path
            elif kind == 'bind':
                if source not in binds:
                    raise ValueError('Every bind mount requires explicit mapping and confirmation: ' + str(source))
            else:
                raise ValueError('Unsupported mount type: ' + str(kind))
    mounted_binds = {m['Source'] for c in containers for m in c.get('Mounts') or [] if m.get('Type') == 'bind'}
    if set(binds) != mounted_binds:
        raise ValueError('Bind mappings must exactly match selected bind mounts')
    protected = [Path('/proc'), Path('/sys'), Path('/dev'), Path('/var/run/docker.sock'), docker_root]
    for source in binds:
        path = Path(source)
        if path == Path('/') or any(overlap(path, denied) for denied in protected):
            raise ValueError('Unsafe bind source range: ' + source)
        audit_tree(path)
        if not path.is_dir():
            raise ValueError('File bind mounts cannot be restored losslessly; only directory binds are supported')
        if (path / BIND_MARKER).exists() or (path / BIND_MARKER).is_symlink():
            raise ValueError('Bind source contains reserved restore marker name')
        sources.append(path)
    for path in volumes.values():
        audit_tree(path)
        sources.append(path)
    assert_no_external_writers(selected_ids, sources)
    network_names = sorted({name for c in containers for name in (c.get('NetworkSettings', {}).get('Networks') or {})})
    networks = js('network', 'inspect', *network_names) if network_names else []
    declaration = {
        'format': FORMAT, 'owner': OWNER, 'selection': selection,
        'engine': {'server_version': info.get('ServerVersion'), 'architecture': info.get('Architecture'),
                   'os': info.get('OperatingSystem'), 'os_type': info.get('OSType')},
        'containers': [container_declaration(c) for c in containers],
        'images': [], 'networks': [{
            'id': n.get('Id'), 'name': n.get('Name'), 'driver': n.get('Driver'), 'scope': n.get('Scope'),
            'internal': n.get('Internal'), 'attachable': n.get('Attachable'), 'enable_ipv6': n.get('EnableIPv6'),
            'labels': n.get('Labels') or {}, 'options': n.get('Options') or {}, 'ipam': n.get('IPAM') or {},
        } for n in networks],
        'data': {'volumes': {name: 'data/volumes/' + str(index) for index, name in enumerate(sorted(volumes))},
                 'binds': {source: {'logical': logical, 'path': 'data/binds/' + logical}
                           for source, logical in sorted(binds.items())}},
        'restore': {
            'contract': 2,
            'platform': {'os': info.get('OSType'), 'architecture': info.get('Architecture')},
            'volumes': {},
        },
    }
    for name in sorted(volumes):
        volume = js('volume', 'inspect', name)[0]
        declaration['restore']['volumes'][name] = {
            'driver': volume.get('Driver'), 'labels': volume.get('Labels') or {},
            'options': volume.get('Options') or {}, 'external': False,
        }
    images = {}
    for container in containers:
        image = image_declaration(container)
        images[image['id']] = image
    declaration['images'] = [images[key] for key in sorted(images)]
    return containers, volumes, binds, declaration


@contextlib.contextmanager
def stopped(containers):
    running = [c['Id'] for c in containers if c.get('State', {}).get('Running')]
    stopped_by_us = []
    try:
        for identity in running:
            current = js('inspect', identity)[0]
            if not current.get('State', {}).get('Running'):
                raise RuntimeError('Container state changed before stop; refusing to alter it')
            docker('stop', identity)
            stopped_state = js('inspect', identity)[0]
            if stopped_state.get('State', {}).get('Running'):
                raise RuntimeError('Selected container did not stop')
            stopped_by_us.append(identity)
        yield
    finally:
        failures = []
        for identity in stopped_by_us:
            try:
                current = js('inspect', identity)[0]
                if current.get('State', {}).get('Running'):
                    continue
                docker('start', identity)
            except Exception:
                failures.append(identity)
        if failures:
            raise RuntimeError(f'Failed to restore {len(failures)} containers stopped by this export; manual intervention required')


class HashReader:
    def __init__(self, stream):
        self.stream, self.value = stream, hashlib.sha256()

    def read(self, size=-1):
        block = self.stream.read(size)
        self.value.update(block)
        return block


def add_bytes(archive, name, payload, entries):
    info = tarfile.TarInfo(name)
    info.size, info.mode = len(payload), 0o600
    archive.addfile(info, io.BytesIO(payload))
    entries.append({'path': name, 'type': 'file', 'size': len(payload),
                    'sha256': hashlib.sha256(payload).hexdigest(), 'mode': 0o600, 'uid': 0, 'gid': 0})


def add_tree(archive, source, root_name, entries):
    source = Path(source)
    items = [(source, root_name)]
    if source.is_dir():
        for current, directories, files in os.walk(source):
            directories.sort()
            files.sort()
            relative = Path(current).relative_to(source)
            items.extend((Path(current) / name, str(PurePosixPath(root_name) / relative.as_posix() / name))
                         for name in directories + files)
    for path, name in items:
        info = path.lstat()
        record = {'path': name, 'type': 'directory' if stat.S_ISDIR(info.st_mode) else 'file',
                  'mode': info.st_mode & 0o7777, 'uid': info.st_uid, 'gid': info.st_gid}
        tarinfo = tarfile.TarInfo(name)
        tarinfo.mode, tarinfo.uid, tarinfo.gid, tarinfo.mtime = record['mode'], info.st_uid, info.st_gid, int(info.st_mtime)
        if record['type'] == 'directory':
            tarinfo.type = tarfile.DIRTYPE
            archive.addfile(tarinfo)
        else:
            tarinfo.size = info.st_size
            record['size'] = info.st_size
            fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
            with os.fdopen(fd, 'rb') as raw:
                before = os.fstat(raw.fileno())
                reader = HashReader(raw)
                archive.addfile(tarinfo, reader)
                after = os.fstat(raw.fileno())
                before_key = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                after_key = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
                if before_key != after_key:
                    raise ValueError('Source changed during export: ' + str(path))
                record['sha256'] = reader.value.hexdigest()
        entries.append(record)


def package(destination, containers, volumes, binds, declaration):
    destination = Path(destination).absolute()
    no_symlink_ancestors(destination, allow_missing=True)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Bundle destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.docker-migration-', dir=destination.parent)
    os.close(fd)
    try:
        with tempfile.TemporaryDirectory(prefix='.docker-images-', dir=destination.parent) as stage:
            image_tar = Path(stage) / 'images.tar'
            image_refs = []
            for image in declaration['images']:
                image_refs.extend(image.get('repo_tags') or [image['id']])
            with image_tar.open('xb') as stream:
                docker('image', 'save', *image_refs, stdout=stream)
            if not image_tar.stat().st_size:
                raise ValueError('Docker image archive is empty')
            with tarfile.open(image_tar, 'r:') as image_archive:
                image_archive.getmembers()
            entries = []
            with tarfile.open(temporary, 'w:gz', format=tarfile.USTAR_FORMAT, dereference=False) as archive:
                add_bytes(archive, DECLARATION, json.dumps(declaration, sort_keys=True, separators=(',', ':')).encode(), entries)
                add_tree(archive, image_tar, 'images/images.tar', entries)
                for index, name in enumerate(sorted(volumes)):
                    add_tree(archive, volumes[name], 'data/volumes/' + str(index), entries)
                for source, logical in sorted(binds.items()):
                    add_tree(archive, source, 'data/binds/' + logical, entries)
                manifest = {'format': FORMAT, 'owner': OWNER, 'entries': entries}
                add_bytes(archive, MANIFEST, json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode(), [])
        os.chmod(temporary, 0o600)
        verify(temporary)
        os.link(temporary, destination)
    finally:
        os.unlink(temporary)


def inspect_bundle(source):
    import gzip
    with gzip.open(source, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
    with tarfile.open(source, 'r:gz') as archive:
        members, names = archive.getmembers(), set()
        for member in members:
            path = PurePosixPath(member.name)
            if (member.name in names or path.is_absolute() or '..' in path.parts or str(path) != member.name
                    or not (member.isfile() or member.isdir())):
                raise ValueError('Unsafe or duplicate bundle member: ' + member.name)
            names.add(member.name)
        if not members or members[-1].name != MANIFEST:
            raise ValueError('Manifest must be the final bundle member')
        if MANIFEST not in names or DECLARATION not in names:
            raise ValueError('Bundle manifest or declaration missing')
        manifest_member = archive.getmember(MANIFEST)
        if not manifest_member.isfile() or manifest_member.size > 64 * 1024 * 1024:
            raise ValueError('Invalid manifest member')
        manifest = json.load(archive.extractfile(manifest_member))
        if set(manifest) != {'format', 'owner', 'entries'} or manifest.get('format') != FORMAT or manifest.get('owner') != OWNER:
            raise ValueError('Unknown bundle manifest')
        records = manifest.get('entries')
        if not isinstance(records, list) or len(records) != len(members) - 1:
            raise ValueError('Manifest entry count mismatch')
        mapped = {}
        required_v1 = {'format', 'owner', 'selection', 'engine', 'containers', 'images', 'networks', 'data'}
        required_v1_restore = required_v1 | {'restore'}
        for record in records:
            if not isinstance(record, dict) or record.get('path') in mapped or record.get('type') not in ('file', 'directory'):
                raise ValueError('Invalid manifest entry')
            expected = {'path', 'type', 'mode', 'uid', 'gid'} | ({'size', 'sha256'} if record['type'] == 'file' else set())
            if set(record) != expected or record['path'] not in names or record['path'] == MANIFEST:
                raise ValueError('Strict manifest member mismatch')
            if (not all(isinstance(record[key], int) and record[key] >= 0 for key in ('uid', 'gid'))
                    or not isinstance(record['mode'], int) or not 0 <= record['mode'] <= 0o7777):
                raise ValueError('Invalid manifest ownership or mode')
            member = archive.getmember(record['path'])
            if record['type'] == 'directory' and not member.isdir():
                raise ValueError('Manifest type mismatch')
            if record['type'] == 'file':
                if (not member.isfile() or not isinstance(record['size'], int) or record['size'] < 0
                        or member.size != record['size'] or not re.fullmatch('[a-f0-9]{64}', record['sha256'])):
                    raise ValueError('Manifest file metadata mismatch')
                if digest(archive.extractfile(member)) != record['sha256']:
                    raise ValueError('Bundle member checksum mismatch: ' + member.name)
            mapped[record['path']] = record
        if set(mapped) != names - {MANIFEST}:
            raise ValueError('Unmanifested bundle member')
        declaration = json.load(archive.extractfile(DECLARATION))
        if (not isinstance(declaration, dict) or set(declaration) not in (required_v1, required_v1_restore)
                or declaration.get('format') != FORMAT or declaration.get('owner') != OWNER):
            raise ValueError('Unknown Docker declaration')
        if not isinstance(declaration['containers'], list) or not declaration['containers']:
            raise ValueError('Docker declaration has no containers')
        if not isinstance(declaration['images'], list) or not declaration['images']:
            raise ValueError('Docker declaration has no images')
        roots = {'images/images.tar'}
        roots.update(declaration.get('data', {}).get('volumes', {}).values())
        roots.update(item.get('path') for item in declaration.get('data', {}).get('binds', {}).values())
        if None in roots or not roots.issubset(mapped):
            raise ValueError('Declared bundle payload missing')
        for name in mapped:
            if name == DECLARATION:
                continue
            if not any(name == root or name.startswith(root + '/') for root in roots):
                raise ValueError('Undeclared bundle payload: ' + name)
        return declaration


def verify(source):
    inspect_bundle(source)
    return True


def export(destination, containers, project, binds, confirmations, accepted):
    if not accepted:
        raise ValueError('Explicit --confirm-stop-writers is required')
    selected, volumes, mappings, declaration = prepare(containers, project, binds, confirmations)
    selected_ids = {item['Id'] for item in selected}
    sources = list(volumes.values()) + [Path(source) for source in mappings]
    with stopped(selected):
        assert_no_external_writers(selected_ids, sources)
        # --no-trunc: plain `docker ps -aq` yields 12-char IDs, which can never
        # match the 64-char selected IDs. Found by the first real-machine run.
        current_ids = set(docker('ps', '-aq', '--no-trunc').decode().split())
        if not selected_ids.issubset(current_ids):
            raise RuntimeError('Docker topology changed after stop; refusing snapshot')
        package(destination, selected, volumes, mappings, declaration)
    return declaration


def _restore_contract(declaration):
    restore = declaration.get('restore')
    if not isinstance(restore, dict) or set(restore) != {'contract', 'platform', 'volumes'} or restore.get('contract') != 2:
        raise ValueError('Bundle predates restore contract 2 (engine-managed masked/readonly paths); export it again')
    if not isinstance(restore['platform'], dict) or set(restore['platform']) != {'os', 'architecture'}:
        raise ValueError('Invalid restore platform contract')
    if not isinstance(restore['volumes'], dict) or set(restore['volumes']) != set(declaration['data']['volumes']):
        raise ValueError('Volume restore contract mismatch')
    required_container = {'id', 'name', 'created', 'image_reference', 'image_id', 'environment', 'entrypoint',
                          'cmd', 'user', 'working_dir', 'restart_policy', 'healthcheck', 'ports', 'exposed_ports',
                          'resources', 'network_mode', 'primary_network', 'networks', 'labels', 'create', 'mounts',
                          'masked_paths', 'readonly_paths', 'original_running'}
    for container in declaration['containers']:
        if not isinstance(container, dict) or set(container) != required_container:
            raise ValueError('Container declaration cannot be restored losslessly')
        if not NAME.fullmatch(container['name'] or ''):
            raise ValueError('Invalid declared container name')
        create = container['create']
        required_create = {'hostname', 'domainname', 'mac_address', 'attach_stdin', 'attach_stdout', 'attach_stderr',
                           'open_stdin', 'stdin_once', 'tty', 'stop_signal', 'stop_timeout', 'readonly_rootfs',
                           'cap_add', 'cap_drop', 'dns', 'dns_options', 'dns_search', 'extra_hosts', 'group_add',
                           'security_opt', 'sysctls', 'ulimits', 'log_config', 'runtime', 'init', 'oom_score_adj'}
        if not isinstance(create, dict) or set(create) != required_create:
            raise ValueError('Container create contract mismatch')
        if container['network_mode'] in ('host',) or str(container['network_mode']).startswith('container:'):
            raise ValueError('Declared network mode cannot be restored safely')
        if container['network_mode'] not in ('default', 'bridge', 'none', *container['networks'].keys()):
            raise ValueError('Declared primary network mode is unavailable')
        if container['primary_network'] not in ('bridge', 'none', *container['networks'].keys()):
            raise ValueError('Invalid primary network endpoint')
        if TRANSACTION_LABEL in container['labels']:
            raise ValueError('Container declaration overrides reserved restore label')
    return restore


def parse_bind_targets(values, declaration):
    expected = {item['logical'] for item in declaration['data']['binds'].values()}
    result = {}
    for value in values:
        if '=' not in value:
            raise ValueError('Bind target must be LOGICAL=ABSOLUTE_TARGET')
        logical, raw = value.split('=', 1)
        path = Path(raw)
        if logical in result or logical not in expected or not path.is_absolute() or str(path.resolve()) != raw:
            raise ValueError('Invalid, duplicate, or undeclared bind target')
        no_symlink_ancestors(path, allow_missing=True)
        result[logical] = path
    if set(result) != expected:
        raise ValueError('Bind targets must exactly match declared logical binds')
    return result


def _network_builtin(name):
    return name in ('bridge', 'host', 'none')


def _existing(kind, name):
    result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', kind, 'inspect', name],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def _subnets(ipam):
    result = []
    if not isinstance(ipam, dict) or set(ipam) - {'Driver', 'Options', 'Config'}:
        raise ValueError('Unsupported network IPAM declaration')
    if ipam.get('Driver') not in (None, '', 'default') or ipam.get('Options'):
        raise ValueError('Nondefault network IPAM driver/options unsupported')
    for config in ipam.get('Config') or []:
        if not isinstance(config, dict) or set(config) - {'Subnet', 'IPRange', 'Gateway', 'AuxiliaryAddresses'}:
            raise ValueError('Unsupported IPAM config field')
        if config.get('AuxiliaryAddresses'):
            raise ValueError('IPAM auxiliary addresses unsupported')
        if config.get('Subnet'):
            subnet = ipaddress.ip_network(config['Subnet'], strict=False)
            for key in ('IPRange',):
                if config.get(key) and not ipaddress.ip_network(config[key], strict=False).subnet_of(subnet):
                    raise ValueError('IPAM range lies outside subnet')
            if config.get('Gateway') and ipaddress.ip_address(config['Gateway']) not in subnet:
                raise ValueError('IPAM gateway lies outside subnet')
            result.append(subnet)
    return result


def _port_conflicts(left, right):
    left_ip, left_port, left_proto = left
    right_ip, right_port, right_proto = right
    if left_port != right_port or left_proto != right_proto:
        return False
    if left_ip == right_ip:
        return True
    left_version = ipaddress.ip_address(left_ip).version
    right_version = ipaddress.ip_address(right_ip).version
    return left_version == right_version and (left_ip in ('0.0.0.0', '::') or right_ip in ('0.0.0.0', '::'))


def _listening_ports():
    result = subprocess.run(['ss', '-H', '-lntu'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    if result.returncode:
        raise ValueError('Cannot inspect host listening sockets with ss')
    found = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 5 or fields[0] not in ('tcp', 'udp'):
            continue
        endpoint = fields[4]
        match = re.search(r'(\[.*\]|[^:]+):(\d+)$', endpoint)
        if match:
            host = match.group(1).strip('[]').replace('*', '::' if ':' in endpoint.rsplit(':', 1)[0] else '0.0.0.0')
            found.add((host, match.group(2), fields[0]))
    return found


def _free_space(path, bytes_needed, inodes_needed):
    candidate = Path(path)
    while not candidate.exists():
        candidate = candidate.parent
    values = os.statvfs(candidate)
    if values.f_bavail * values.f_frsize < bytes_needed:
        raise ValueError('Insufficient free space at ' + str(candidate))
    if values.f_favail and values.f_favail < inodes_needed:
        raise ValueError('Insufficient free inodes at ' + str(candidate))


def preflight(source, bind_values, external_policy='reject', resume_journal=None):
    """Perform target checks without creating files or Docker resources."""
    declaration = inspect_bundle(source)
    restore = _restore_contract(declaration)
    info, docker_root = daemon_info()
    platform = restore['platform']
    if (info.get('OSType') != platform['os']
            or _norm_arch(info.get('Architecture')) != _norm_arch(platform['architecture'])):
        raise ValueError('Target Docker OS/architecture differs from bundle')
    owned = {(item['kind'], item['name']): item for item in (resume_journal or {}).get('created', [])
             if not item.get('rolled_back')}
    target_images = js('image', 'inspect', *docker('image', 'ls', '-q', '--no-trunc').decode().split()) if docker('image', 'ls', '-q', '--no-trunc').decode().split() else []
    target_tags = {tag for image in target_images for tag in image.get('RepoTags') or []}
    declared_tags = set()
    for image in declaration['images']:
        tags = image.get('repo_tags')
        if not isinstance(tags, list) or any(not isinstance(tag, str) or not tag for tag in tags):
            raise ValueError('Bundle lacks protected image RepoTags; export it again')
        if declared_tags.intersection(tags):
            raise ValueError('Duplicate RepoTag across declared images')
        declared_tags.update(tags)
        if target_tags.intersection(tags):
            raise ValueError('Declared image RepoTag already exists on target')
        if (image.get('os') != info.get('OSType')
                or _norm_arch(image.get('architecture')) != _norm_arch(info.get('Architecture'))):
            raise ValueError('Image OS/architecture is incompatible with target')
        if _existing('image', image.get('id', '')) and ('image', image['id']) not in owned:
            raise ValueError('Declared image already exists on clean target: ' + str(image.get('id')))
        if image.get('variant') not in (None, ''):
            target_variant = info.get('Variant')
            if target_variant and target_variant != image['variant']:
                raise ValueError('Image architecture variant is incompatible with target')
    if declaration['selection'].get('kind') == 'compose-project':
        docker('compose', 'version')
    if external_policy != 'reject':
        raise ValueError('Only --external-volume-policy=reject is supported; reuse cannot prove a clean target')
    targets = parse_bind_targets(bind_values, declaration)
    names = [item['name'] for item in declaration['containers']]
    if len(names) != len(set(names)) or any(_existing('container', name) and ('container', name) not in owned for name in names):
        raise ValueError('Declared container name already exists or is duplicated')
    volume_contract = restore['volumes']
    for name, spec in volume_contract.items():
        if (not NAME.fullmatch(name) or not isinstance(spec, dict)
                or set(spec) != {'driver', 'labels', 'options', 'external'}):
            raise ValueError('Invalid volume contract')
        if spec['external'] or spec['driver'] != 'local' or spec['options']:
            raise ValueError('External, nonlocal, or optioned volumes cannot be restored losslessly')
        if TRANSACTION_LABEL in spec['labels']:
            raise ValueError('Volume declaration overrides reserved restore label')
        if _existing('volume', name) and ('volume', name) not in owned:
            raise ValueError('Declared volume already exists: ' + name)
    declared_networks = {item['name']: item for item in declaration['networks']}
    if len(declared_networks) != len(declaration['networks']):
        raise ValueError('Duplicate network declaration')
    all_networks = js('network', 'inspect', *docker('network', 'ls', '-q').decode().split()) if docker('network', 'ls', '-q').decode().split() else []
    occupied = [(n.get('Name'), subnet) for n in all_networks for subnet in _subnets(n.get('IPAM') or {})]
    for name, network in declared_networks.items():
        if TRANSACTION_LABEL in (network.get('labels') or {}):
            raise ValueError('Network declaration overrides reserved restore label')
        if not NAME.fullmatch(name or '') or network.get('driver') != 'bridge' or network.get('scope') != 'local':
            if not _network_builtin(name):
                raise ValueError('Only local bridge networks can be recreated')
        wanted = _subnets(network.get('ipam') or {})
        if _network_builtin(name):
            if not _existing('network', name):
                raise ValueError('Required built-in network missing: ' + name)
        elif _existing('network', name) and ('network', name) not in owned:
            raise ValueError('Declared network already exists: ' + name)
        for subnet in wanted:
            if any(subnet.overlaps(other) and owner != name for owner, other in occupied):
                raise ValueError('Declared network subnet overlaps target network: ' + str(subnet))
    used_ports = _listening_ports()
    ids = docker('ps', '-aq').decode().split()
    for current in js('inspect', *ids) if ids else []:
        for container_port, bindings in (current.get('HostConfig', {}).get('PortBindings') or {}).items():
            protocol = container_port.rsplit('/', 1)[-1]
            for binding in bindings or []:
                used_ports.add((binding.get('HostIp') or '0.0.0.0', str(binding.get('HostPort') or ''), protocol))
    wanted_ports = set()
    for container in declaration['containers']:
        for port, bindings in container['ports'].items():
            if not re.fullmatch(r'[1-9][0-9]{0,4}/(tcp|udp|sctp)', port):
                raise ValueError('Invalid declared container port')
            protocol = port.rsplit('/', 1)[-1]
            for binding in bindings or []:
                host_ip, host_port = binding.get('HostIp') or '0.0.0.0', str(binding.get('HostPort') or '')
                ipaddress.ip_address(host_ip)
                if not host_port.isdigit() or not 1 <= int(host_port) <= 65535:
                    raise ValueError('Dynamic or invalid host ports cannot be restored losslessly')
                key = (host_ip, host_port, protocol)
                if any(_port_conflicts(key, other) for other in wanted_ports | used_ports):
                    raise ValueError('Declared host port is duplicated, listening, or occupied')
                wanted_ports.add(key)
    for path in targets.values():
        if path.exists() and (not path.is_dir() or any(path.iterdir())):
            raise ValueError('Bind target must be absent or an empty directory: ' + str(path))
        if resume_journal is None and path.exists():
            raise ValueError('Restore requires absent bind targets so rollback never deletes pre-existing paths: ' + str(path))
    with tarfile.open(source, 'r:gz') as archive:
        records = json.load(archive.extractfile(MANIFEST))['entries']
    total = sum(item.get('size', 0) for item in records)
    inode_count = len(records) + len(declaration['containers']) + len(declaration['networks']) + len(volume_contract) + 32
    _free_space(docker_root, total * 2 + 64 * 1024 * 1024, inode_count)
    for path in targets.values():
        _free_space(path, total + 16 * 1024 * 1024, inode_count)
    return declaration, targets


def _fsync_directory(path):
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _assert_private(path, mode, directory=False):
    info = Path(path).lstat()
    expected_type = stat.S_ISDIR if directory else stat.S_ISREG
    if stat.S_ISLNK(info.st_mode) or not expected_type(info.st_mode):
        raise ValueError('Unsafe restore journal path')
    if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != mode:
        raise ValueError('Restore journal paths must be root-owned and private')


def _validate_journal_path(path, require_file=True):
    path = Path(path)
    if path.parent.parent != JOURNAL_BASE or path.name != 'journal.json' or not TX.fullmatch(path.parent.name):
        raise ValueError('Journal must reside in the fixed restore directory')
    no_symlink_ancestors(path, allow_missing=not require_file)
    _assert_private(JOURNAL_BASE, 0o700, directory=True)
    _assert_private(path.parent, 0o700, directory=True)
    if require_file:
        _assert_private(path, 0o600)


def save_journal(path, journal):
    path = Path(path)
    _validate_journal_path(path, require_file=path.exists())
    payload = (json.dumps(journal, sort_keys=True, separators=(',', ':')) + '\n').encode()
    temporary = path.with_name('.' + path.name + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def _begin_resource(path, journal, kind, name):
    item = {'kind': kind, 'name': name, 'id': None, 'status': 'pending'}
    journal['created'].append(item)
    save_journal(path, journal)
    return item


def _finish_resource(path, journal, item, identity):
    item['id'], item['status'] = identity, 'created'
    save_journal(path, journal)


def _journal_item(journal, kind, name):
    return next((item for item in journal['created'] if item['kind'] == kind and item['name'] == name
                 and not item.get('rolled_back')), None)


def _extract_verified(source, stage):
    inspect_bundle(source)
    stage.mkdir(mode=0o700)
    _fsync_directory(stage.parent)
    with tarfile.open(source, 'r:gz') as archive:
        manifest = json.load(archive.extractfile(MANIFEST))
        for record in manifest['entries']:
            target = stage / PurePosixPath(record['path'])
            if record['type'] == 'directory':
                target.mkdir(parents=True, exist_ok=False)
                os.chmod(target, record['mode'])
            else:
                target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
                with os.fdopen(fd, 'wb') as output, archive.extractfile(record['path']) as incoming:
                    shutil.copyfileobj(incoming, output)
                    output.flush()
                    os.fsync(output.fileno())
                os.chmod(target, record['mode'])
            try:
                os.chown(target, record['uid'], record['gid'], follow_symlinks=False)
            except PermissionError:
                raise ValueError('Restore requires root to preserve ownership') from None
    _fsync_directory(stage)


def _copy_tree(source, target):
    source, target = Path(source), Path(target)
    if not source.is_dir() or not target.is_dir():
        raise ValueError('Restore data roots must be directories')
    for child in source.iterdir():
        destination = target / child.name
        if destination.exists() or destination.is_symlink():
            raise ValueError('Refusing to copy into an existing restore path')
        if child.is_dir():
            destination.mkdir()
            _copy_tree(child, destination)
        else:
            shutil.copy2(child, destination, follow_symlinks=False)
        info = child.stat(follow_symlinks=False)
        os.chown(destination, info.st_uid, info.st_gid, follow_symlinks=False)
        if child.is_dir():
            shutil.copystat(child, destination, follow_symlinks=False)
    root_info = source.stat(follow_symlinks=False)
    os.chown(target, root_info.st_uid, root_info.st_gid, follow_symlinks=False)
    shutil.copystat(source, target, follow_symlinks=False)


@contextlib.contextmanager
def _bind_fds(target, create=False):
    """Pin the bind parent and root; all mutation must use these descriptors."""
    target = Path(target)
    no_symlink_ancestors(target.parent)
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    parent_fd = os.open(target.parent, flags)
    try:
        if create:
            os.mkdir(target.name, 0o700, dir_fd=parent_fd)
            os.fsync(parent_fd)
        root_fd = os.open(target.name, flags, dir_fd=parent_fd)
        try:
            yield parent_fd, target.name, root_fd
        finally:
            os.close(root_fd)
    finally:
        os.close(parent_fd)


def _marker_owned_fd(root_fd, transaction):
    try:
        info = os.stat(BIND_MARKER, dir_fd=root_fd, follow_symlinks=False)
        fd = os.open(BIND_MARKER, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0), dir_fd=root_fd)
        with os.fdopen(fd) as stream:
            payload = stream.read()
    except (FileNotFoundError, OSError):
        return False
    return (stat.S_ISREG(info.st_mode) and info.st_uid == 0 and stat.S_IMODE(info.st_mode) == 0o600
            and payload == transaction + '\n')


def _create_bind_target(target, transaction):
    with _bind_fds(target, create=True) as (_, _, root_fd):
        fd = os.open(BIND_MARKER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0),
                     0o600, dir_fd=root_fd)
        with os.fdopen(fd, 'w') as stream:
            stream.write(transaction + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.fsync(root_fd)


def _owned_bind(target, transaction):
    try:
        with _bind_fds(target) as (_, _, root_fd):
            return _marker_owned_fd(root_fd, transaction)
    except (FileNotFoundError, OSError, ValueError):
        return False


def _remove_bind(target, transaction):
    with _bind_fds(target) as (parent_fd, name, root_fd):
        if not _marker_owned_fd(root_fd, transaction):
            raise ValueError('Bind ownership marker missing or changed')
        parent_before = os.fstat(parent_fd)
        root_before = os.fstat(root_fd)
        _clear_fd(root_fd, expected_parent=parent_fd, expected_name=name,
                  expected_root=(root_before.st_dev, root_before.st_ino))
        os.fsync(root_fd)
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != (root_before.st_dev, root_before.st_ino):
            raise ValueError('Bind target switched during rollback')
        os.rmdir(name, dir_fd=parent_fd)
        if (os.fstat(parent_fd).st_dev, os.fstat(parent_fd).st_ino) != (parent_before.st_dev, parent_before.st_ino):
            raise ValueError('Bind parent switched during rollback')
        os.fsync(parent_fd)


def _clear_fd(directory_fd, preserve=(), expected_parent=None, expected_name=None, expected_root=None):
    if expected_parent is not None:
        current = os.stat(expected_name, dir_fd=expected_parent, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != expected_root:
            raise ValueError('Bind target switched during rollback')
    for name in os.listdir(directory_fd):
        if name in preserve:
            continue
        info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(info.st_mode):
            child_fd = os.open(name, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0),
                               dir_fd=directory_fd)
            try:
                fixed = os.fstat(child_fd)
                if (fixed.st_dev, fixed.st_ino) != (info.st_dev, info.st_ino):
                    raise ValueError('Bind child switched during rollback')
                _clear_fd(child_fd, expected_parent=directory_fd, expected_name=name,
                          expected_root=(fixed.st_dev, fixed.st_ino))
                current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                if (current.st_dev, current.st_ino) != (fixed.st_dev, fixed.st_ino):
                    raise ValueError('Bind child switched during rollback')
                if expected_parent is not None:
                    root_now = os.stat(expected_name, dir_fd=expected_parent, follow_symlinks=False)
                    if (root_now.st_dev, root_now.st_ino) != expected_root:
                        raise ValueError('Bind target switched during rollback')
                os.rmdir(name, dir_fd=directory_fd)
            finally:
                os.close(child_fd)
        else:
            if expected_parent is not None:
                root_now = os.stat(expected_name, dir_fd=expected_parent, follow_symlinks=False)
                if (root_now.st_dev, root_now.st_ino) != expected_root:
                    raise ValueError('Bind target switched during rollback')
            current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if (current.st_dev, current.st_ino, current.st_mode) != (info.st_dev, info.st_ino, info.st_mode):
                raise ValueError('Bind entry switched during rollback')
            os.unlink(name, dir_fd=directory_fd)


def _copy_tree_fd(source, target_fd):
    source = Path(source)
    for child in source.iterdir():
        info = child.stat(follow_symlinks=False)
        if child.is_dir():
            os.mkdir(child.name, stat.S_IMODE(info.st_mode), dir_fd=target_fd)
            child_fd = os.open(child.name, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0),
                               dir_fd=target_fd)
            try:
                _copy_tree_fd(child, child_fd)
                os.fchown(child_fd, info.st_uid, info.st_gid)
                os.fchmod(child_fd, stat.S_IMODE(info.st_mode))
                os.fsync(child_fd)
            finally:
                os.close(child_fd)
        elif child.is_file():
            fd = os.open(child.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0),
                         stat.S_IMODE(info.st_mode), dir_fd=target_fd)
            with child.open('rb') as incoming, os.fdopen(fd, 'wb') as output:
                shutil.copyfileobj(incoming, output)
                output.flush()
                os.fchown(output.fileno(), info.st_uid, info.st_gid)
                os.fchmod(output.fileno(), stat.S_IMODE(info.st_mode))
                os.fsync(output.fileno())
        else:
            raise ValueError('Special restore data entry unsupported')
    root = source.stat(follow_symlinks=False)
    os.fchown(target_fd, root.st_uid, root.st_gid)
    os.fchmod(target_fd, stat.S_IMODE(root.st_mode))
    os.fsync(target_fd)


def _copy_bind_data(path, journal, item, source, target, transaction):
    if item.get('data_status') == 'created':
        return
    item['data_status'] = 'pending'
    save_journal(path, journal)
    with _bind_fds(target) as (parent_fd, name, root_fd):
        root_before = os.fstat(root_fd)
        if not _marker_owned_fd(root_fd, transaction):
            raise ValueError('Bind ownership marker changed during restore')
        _clear_fd(root_fd, preserve=(BIND_MARKER,))
        _copy_tree_fd(source, root_fd)
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != (root_before.st_dev, root_before.st_ino):
            raise ValueError('Bind target switched during restore')
        if not _marker_owned_fd(root_fd, transaction):
            raise ValueError('Bind ownership marker changed during restore')
    item['data_status'] = 'created'
    save_journal(path, journal)


def _clear_directory(target, preserve=()):
    preserved = set(preserve)
    for child in Path(target).iterdir():
        if child.name in preserved:
            continue
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()


def _copy_data(path, journal, item, source, target, preserve=()):
    if item.get('data_status') == 'created':
        return
    item['data_status'] = 'pending'
    save_journal(path, journal)
    _clear_directory(target, preserve)
    _copy_tree(source, target)
    item['data_status'] = 'created'
    save_journal(path, journal)


def _resource_owned(kind, name, transaction):
    if not _existing(kind, name):
        return None
    current = js(kind, 'inspect', name)[0]
    labels = current.get('Config', {}).get('Labels') if kind == 'container' else current.get('Labels')
    if (labels or {}).get(TRANSACTION_LABEL) != transaction:
        raise ValueError('Pending resource exists without transaction ownership: ' + name)
    return current


def _network_create(network, transaction):
    args = ['network', 'create', '--driver', network['driver']]
    if network.get('internal'):
        args.append('--internal')
    if network.get('attachable'):
        args.append('--attachable')
    if network.get('enable_ipv6'):
        args.append('--ipv6')
    for key, value in sorted((network.get('labels') or {}).items()):
        args.extend(('--label', key + '=' + value))
    for key, value in sorted((network.get('options') or {}).items()):
        args.extend(('--opt', key + '=' + value))
    args.extend(('--label', TRANSACTION_LABEL + '=' + transaction))
    for config in (network.get('ipam') or {}).get('Config') or []:
        for field, option in (('Subnet', '--subnet'), ('IPRange', '--ip-range'), ('Gateway', '--gateway')):
            if config.get(field):
                args.extend((option, config[field]))
    args.append(network['name'])
    return docker(*args).decode().strip()


def _publish_spec(host, host_port, container_port):
    if host and ipaddress.ip_address(host).version == 6:
        host = '[' + host + ']'
    return (host + ':' if host else '') + str(host_port) + ':' + container_port


def _create_container(container, bind_targets, transaction):
    args = ['container', 'create', '--name', container['name']]
    create = container['create']
    scalar = [('hostname', '--hostname'), ('domainname', '--domainname'), ('user', '--user'),
              ('working_dir', '--workdir')]
    merged = dict(create, user=container['user'], working_dir=container['working_dir'])
    for key, option in scalar:
        if merged.get(key):
            args.extend((option, str(merged[key])))
    flags = [('tty', '--tty'), ('open_stdin', '--interactive'), ('readonly_rootfs', '--read-only')]
    for key, option in flags:
        if create.get(key):
            args.append(option)
    if create.get('stop_signal'):
        args.extend(('--stop-signal', create['stop_signal']))
    if create.get('stop_timeout') is not None:
        args.extend(('--stop-timeout', str(create['stop_timeout'])))
    if create.get('init') is True:
        args.append('--init')
    if create.get('runtime'):
        args.extend(('--runtime', create['runtime']))
    if create.get('oom_score_adj'):
        args.extend(('--oom-score-adj', str(create['oom_score_adj'])))
    repeated = [('cap_add', '--cap-add'), ('cap_drop', '--cap-drop'), ('dns', '--dns'),
                ('dns_options', '--dns-option'), ('dns_search', '--dns-search'), ('extra_hosts', '--add-host'),
                ('group_add', '--group-add'), ('security_opt', '--security-opt')]
    for key, option in repeated:
        for value in create.get(key) or []:
            args.extend((option, str(value)))
    for key, value in sorted((create.get('sysctls') or {}).items()):
        args.extend(('--sysctl', key + '=' + str(value)))
    for limit in create.get('ulimits') or []:
        args.extend(('--ulimit', '%s=%s:%s' % (limit['Name'], limit['Soft'], limit['Hard'])))
    log = create.get('log_config') or {}
    if log.get('Type'):
        args.extend(('--log-driver', log['Type']))
    for key, value in sorted((log.get('Config') or {}).items()):
        args.extend(('--log-opt', key + '=' + value))
    restart = container.get('restart_policy') or {}
    if restart.get('Name'):
        policy = restart['Name']
        if policy == 'on-failure' and restart.get('MaximumRetryCount'):
            policy += ':' + str(restart['MaximumRetryCount'])
        args.extend(('--restart', policy))
    health = container.get('healthcheck') or {}
    test = health.get('Test') or []
    if test and test[0] == 'NONE':
        args.append('--no-healthcheck')
    elif test:
        args.extend(('--health-cmd', test[1]))
        for key, option in (('Interval', '--health-interval'), ('Timeout', '--health-timeout'),
                            ('StartPeriod', '--health-start-period')):
            if health.get(key):
                args.extend((option, str(health[key]) + 'ns'))
        if health.get('Retries'):
            args.extend(('--health-retries', str(health['Retries'])))
    resource_options = {'Memory': '--memory', 'MemoryReservation': '--memory-reservation', 'MemorySwap': '--memory-swap',
                        'MemorySwappiness': '--memory-swappiness', 'NanoCpus': '--cpus', 'CpuShares': '--cpu-shares',
                        'CpuPeriod': '--cpu-period', 'CpuQuota': '--cpu-quota', 'CpusetCpus': '--cpuset-cpus',
                        'CpusetMems': '--cpuset-mems', 'PidsLimit': '--pids-limit', 'ShmSize': '--shm-size'}
    for key, option in resource_options.items():
        value = container['resources'].get(key)
        if value not in (None, '', 0, -1):
            if key == 'NanoCpus':
                value = str(value / 1_000_000_000)
            args.extend((option, str(value)))
    if container['resources'].get('OomKillDisable'):
        args.append('--oom-kill-disable')
    for value in container['environment']:
        args.extend(('--env', value))
    for key, value in sorted(container['labels'].items()):
        args.extend(('--label', key + '=' + value))
    args.extend(('--label', TRANSACTION_LABEL + '=' + transaction))
    if container.get('entrypoint'):
        if not isinstance(container['entrypoint'], list) or len(container['entrypoint']) != 1:
            raise ValueError('Multi-element entrypoint cannot be represented losslessly by docker create CLI')
        args.extend(('--entrypoint', container['entrypoint'][0]))
    for port in sorted(container['exposed_ports']):
        args.extend(('--expose', port))
    for port, bindings in sorted(container['ports'].items()):
        for binding in bindings or []:
            host = binding.get('HostIp') or ''
            args.extend(('--publish', _publish_spec(host, binding['HostPort'], port)))
    source_to_logical = {source: item['logical'] for source, item in bind_targets['_declaration'].items()}
    for mount in container['mounts']:
        if mount['Type'] == 'volume':
            source = mount['Name']
        elif mount['Type'] == 'bind':
            source = str(bind_targets[source_to_logical[mount['Source']]])
        else:
            raise ValueError('Unsupported declared mount')
        spec = ['type=' + mount['Type'], 'src=' + source, 'dst=' + mount['Destination']]
        if not mount.get('RW'):
            spec.append('readonly')
        if mount.get('Propagation') and mount['Propagation'] != '':
            spec.append('bind-propagation=' + mount['Propagation'])
        args.extend(('--mount', ','.join(spec)))
    primary = container['primary_network']
    first_network = None if primary == 'none' else primary
    args.extend(('--network', primary))
    if primary in container['networks']:
        endpoint = container['networks'][primary]
        # Static IPs only for user-defined networks: on the default bridge the
        # engine assigns addresses dynamically and rejects --ip, and the recorded
        # address is engine-assigned audit data anyway (two-host finding).
        if not _network_builtin(primary):
            if endpoint.get('ip_address'):
                args.extend(('--ip', endpoint['ip_address']))
            if endpoint.get('global_ipv6_address'):
                args.extend(('--ip6', endpoint['global_ipv6_address']))
        for alias in endpoint.get('aliases') or []:
            if alias != container['name']:
                args.extend(('--network-alias', alias))
    # Reference the image the way the original create did (Config.Image, a tag);
    # the engine-storage-specific image ID may not exist on the target store.
    args.append(container['image_reference'] or container['image_id'])
    args.extend(container.get('cmd') or [])
    return docker(*args).decode().strip(), first_network


def load_journal(transaction):
    if not TX.fullmatch(transaction):
        raise ValueError('Invalid transaction ID')
    path = JOURNAL_BASE / transaction / 'journal.json'
    _validate_journal_path(path)
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd) as stream:
        journal = json.load(stream)
    if journal.get('owner') != JOURNAL_OWNER or journal.get('transaction') != transaction:
        raise ValueError('Unknown restore journal')
    return path, journal


def _image_snapshot():
    ids = docker('image', 'ls', '-aq', '--no-trunc').decode().split()
    images = js('image', 'inspect', *ids) if ids else []
    return {'ids': sorted({image['Id'] for image in images}),
            'tags': sorted({tag for image in images for tag in image.get('RepoTags') or []})}


def _rollback_images(journal):
    record = journal.get('image_load')
    if not record or record.get('rolled_back'):
        return
    before_ids, before_tags = set(record['before']['ids']), set(record['before']['tags'])
    current = _image_snapshot()
    for tag in sorted(set(current['tags']) - before_tags):
        if tag in record['declared_tags']:
            docker('image', 'rm', tag)
    current_ids = set(_image_snapshot()['ids'])
    for identity in sorted((current_ids - before_ids).intersection(record['declared_ids'])):
        docker('image', 'rm', identity)
    record['rolled_back'] = True


def rollback(transaction):
    path, journal = load_journal(transaction)
    failures = []
    for item in reversed(journal['created']):
        try:
            if item.get('rolled_back'):
                continue
            if item['kind'] == 'container':
                if item.get('status') == 'pending' and not _existing('container', item['name']):
                    item['rolled_back'] = True
                    save_journal(path, journal)
                    continue
                current = js('container', 'inspect', item['name'])[0]
                labels = current.get('Config', {}).get('Labels') or {}
                if labels.get(TRANSACTION_LABEL) != transaction:
                    raise ValueError('Container ownership label changed')
                if item.get('id') and current['Id'] != item['id']:
                    raise ValueError('Container identity changed')
                docker('container', 'rm', '-f', current['Id'])
            elif item['kind'] == 'network':
                if item.get('status') == 'pending' and not _existing('network', item['name']):
                    item['rolled_back'] = True
                    save_journal(path, journal)
                    continue
                current = js('network', 'inspect', item['name'])[0]
                if (current.get('Labels') or {}).get(TRANSACTION_LABEL) != transaction:
                    raise ValueError('Network ownership label changed')
                if item.get('id') and current['Id'] != item['id']:
                    raise ValueError('Network identity changed')
                docker('network', 'rm', current['Id'])
            elif item['kind'] == 'volume':
                if item.get('status') == 'pending' and not _existing('volume', item['name']):
                    item['rolled_back'] = True
                    save_journal(path, journal)
                    continue
                current = js('volume', 'inspect', item['name'])[0]
                if (current.get('Labels') or {}).get(TRANSACTION_LABEL) != transaction:
                    raise ValueError('Volume ownership label changed')
                docker('volume', 'rm', item['name'])
            elif item['kind'] == 'image':
                # Images are never transaction-owned exclusively: loading may add tags to shared content.
                pass
            elif item['kind'] == 'bind':
                target = Path(item['name'])
                if target.exists():
                    if item.get('status') != 'created' or not _owned_bind(target, transaction):
                        raise ValueError('Bind ownership marker missing or changed')
                    _remove_bind(target, transaction)
            item['rolled_back'] = True
            save_journal(path, journal)
        except Exception:
            failures.append(item['kind'] + ':' + item['name'])
    journal['state'] = 'rolled-back' if not failures else 'rollback-failed'
    journal['rollback_failures'] = failures
    save_journal(path, journal)
    try:
        _rollback_images(journal)
        save_journal(path, journal)
    except Exception:
        failures.append('images')
        journal['state'] = 'rollback-failed'
        journal['rollback_failures'] = failures
        save_journal(path, journal)
    if failures:
        raise RuntimeError('Rollback incomplete; journal retained: ' + ', '.join(failures))
    return journal


def _execute_restore(path, journal):
    declaration = journal['declaration']
    stage = path.parent / 'staging'
    targets = {key: Path(value) for key, value in journal['bind_targets'].items()}
    targets['_declaration'] = declaration['data']['binds']
    if journal['step'] < 1:
        _extract_verified(journal['bundle'], stage)
        journal['step'] = 1
        save_journal(path, journal)
    if journal['step'] < 2:
        if 'image_load' not in journal:
            journal['image_load'] = {
                'before': _image_snapshot(),
                'declared_ids': sorted(image['id'] for image in declaration['images']),
                'declared_tags': sorted(tag for image in declaration['images'] for tag in image.get('repo_tags') or []),
                'status': 'pending', 'rolled_back': False,
            }
            save_journal(path, journal)
        if not all(_existing('image', image['id']) for image in declaration['images']):
            docker('image', 'load', '--input', str(stage / 'images/images.tar'))
        for image in declaration['images']:
            # Image IDs are engine-storage specific: containerd-snapshotter daemons
            # report manifest digests as the image ID, classic stores report config
            # digests, and `docker load` does not carry the digest into the other
            # scheme (RepoDigests come back empty). The bundle payload is already
            # checksum-verified, so identity is established by the declared
            # RepoTags; the loaded ID is audit-only. Found by the two-host run.
            loaded = None
            for ref in [image['id']] + sorted(image.get('repo_tags') or []):
                if _existing('image', ref):
                    loaded = js('image', 'inspect', ref)[0]
                    break
            if loaded is None:
                raise RuntimeError('Loaded image not found: ' + str(image.get('repo_tags')))
            if set(loaded.get('RepoTags') or []) != set(image.get('repo_tags') or []):
                raise RuntimeError('Loaded image RepoTags do not match declaration')
        journal['image_load']['status'] = 'created'
        journal['step'] = 2
        save_journal(path, journal)
    if journal['step'] < 3:
        for network in declaration['networks']:
            if not _network_builtin(network['name']):
                prior = _journal_item(journal, 'network', network['name'])
                current = _resource_owned('network', network['name'], journal['transaction']) if prior else None
                item = prior or _begin_resource(path, journal, 'network', network['name'])
                if current:
                    if item.get('status') != 'created':
                        _finish_resource(path, journal, item, current['Id'])
                else:
                    identity = _network_create(network, journal['transaction'])
                    _finish_resource(path, journal, item, identity)
        for name, root in declaration['data']['volumes'].items():
            spec = declaration['restore']['volumes'][name]
            args = ['volume', 'create', '--driver', spec['driver']]
            for key, value in sorted(spec['labels'].items()):
                args.extend(('--label', key + '=' + value))
            args.extend(('--label', TRANSACTION_LABEL + '=' + journal['transaction']))
            args.append(name)
            item = _journal_item(journal, 'volume', name) or _begin_resource(path, journal, 'volume', name)
            current = _resource_owned('volume', name, journal['transaction'])
            if current:
                if item.get('status') != 'created':
                    _finish_resource(path, journal, item, name)
            else:
                docker(*args)
                _finish_resource(path, journal, item, name)
            mountpoint = Path(js('volume', 'inspect', name)[0]['Mountpoint'])
            _copy_data(path, journal, item, stage / root, mountpoint)
        for bind in declaration['data']['binds'].values():
            target = targets[bind['logical']]
            item = _journal_item(journal, 'bind', str(target)) or _begin_resource(path, journal, 'bind', str(target))
            if item.get('status') == 'pending':
                if target.exists():
                    if not _owned_bind(target, journal['transaction']):
                        raise ValueError('Pending bind target exists without ownership marker')
                    _finish_resource(path, journal, item, str(target))
                else:
                    _create_bind_target(target, journal['transaction'])
                    _finish_resource(path, journal, item, str(target))
            elif not _owned_bind(target, journal['transaction']):
                raise ValueError('Recorded bind ownership marker changed')
            _copy_bind_data(path, journal, item, stage / bind['path'], target, journal['transaction'])
        journal['step'] = 3
        save_journal(path, journal)
    if journal['step'] < 4:
        for container in declaration['containers']:
            prior = _journal_item(journal, 'container', container['name'])
            item = prior or _begin_resource(path, journal, 'container', container['name'])
            current = _resource_owned('container', container['name'], journal['transaction'])
            if current:
                identity = current['Id']
                if item.get('status') != 'created':
                    _finish_resource(path, journal, item, identity)
            else:
                identity, _ = _create_container(container, targets, journal['transaction'])
                _finish_resource(path, journal, item, identity)
            attached = (js('container', 'inspect', identity)[0].get('NetworkSettings', {}).get('Networks') or {})
            for name, endpoint in container['networks'].items():
                if name in attached:
                    continue
                args = ['network', 'connect']
                if endpoint.get('ip_address'):
                    args.extend(('--ip', endpoint['ip_address']))
                if endpoint.get('global_ipv6_address'):
                    args.extend(('--ip6', endpoint['global_ipv6_address']))
                for alias in endpoint.get('aliases') or []:
                    if alias != container['name']:
                        args.extend(('--alias', alias))
                args.extend((name, identity))
                docker(*args)
        journal['step'] = 4
        save_journal(path, journal)
    if journal['step'] < 5:
        for container in declaration['containers']:
            if container['original_running']:
                docker('container', 'start', container['name'])
        deadline = time.monotonic() + journal['health_timeout']
        while True:
            pending = []
            for container in declaration['containers']:
                state = js('container', 'inspect', container['name'])[0]['State']
                if container['original_running'] and not state.get('Running'):
                    raise RuntimeError('Restored container exited before verification: ' + container['name'])
                if container['original_running'] and container.get('healthcheck'):
                    status = (state.get('Health') or {}).get('Status')
                    if status == 'unhealthy':
                        raise RuntimeError('Restored container is unhealthy: ' + container['name'])
                    if status != 'healthy':
                        pending.append(container['name'])
            if not pending:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Health verification timed out: ' + ', '.join(pending))
            time.sleep(1)
        journal['step'] = 5
        journal['state'] = 'complete'
        save_journal(path, journal)
    return journal


def restore(source, bind_values, confirmed, external_policy='reject', health_timeout=120):
    if not confirmed:
        raise ValueError('Explicit --confirm-clean-target is required')
    declaration, targets = preflight(source, bind_values, external_policy)
    no_symlink_ancestors(JOURNAL_BASE, allow_missing=True)
    JOURNAL_BASE.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(JOURNAL_BASE, 0o700)
    if os.geteuid() != 0:
        raise ValueError('Restore journal requires root ownership')
    _assert_private(JOURNAL_BASE, 0o700, directory=True)
    transaction = uuid.uuid4().hex
    root = JOURNAL_BASE / transaction
    os.mkdir(root, 0o700)
    journal_path = root / 'journal.json'
    journal = {'owner': JOURNAL_OWNER, 'transaction': transaction, 'state': 'running', 'step': 0,
               'bundle': str(Path(source).resolve()), 'bundle_sha256': digest(open(source, 'rb')),
               'bind_targets': {key: str(value) for key, value in targets.items()}, 'declaration': declaration,
               'created': [], 'health_timeout': health_timeout}
    save_journal(journal_path, journal)
    try:
        return _execute_restore(journal_path, journal)
    except Exception as error:
        journal['state'] = 'failed'
        # Keep the underlying reason: swallowing it left target-side failures
        # undebuggable (found by the two-host acceptance run).
        journal['error'] = '%s: %s' % (type(error).__name__, error)
        save_journal(journal_path, journal)
        raise RuntimeError('Restore failed; use rollback or resume with transaction ' + transaction) from None


def resume(transaction):
    path, journal = load_journal(transaction)
    if journal['state'] not in ('failed', 'running'):
        raise ValueError('Only failed or interrupted transactions can be resumed')
    with open(journal['bundle'], 'rb') as stream:
        if digest(stream) != journal['bundle_sha256']:
            raise ValueError('Bundle changed since transaction began')
    declaration = inspect_bundle(journal['bundle'])
    _restore_contract(declaration)
    if declaration != journal['declaration']:
        raise ValueError('Bundle declaration changed')
    # Resume never adopts target resources: every prior mutation must still carry this transaction identity.
    for item in journal['created']:
        if item.get('rolled_back'):
            raise ValueError('A partially rolled back transaction cannot be resumed')
        if item['kind'] == 'container':
            if not _existing('container', item['name']):
                if item.get('status') == 'pending':
                    continue
                raise ValueError('Recorded container is missing')
            current = js('container', 'inspect', item['name'])[0]
            if ((current.get('Config', {}).get('Labels') or {}).get(TRANSACTION_LABEL) != transaction
                    or item.get('id') and current['Id'] != item['id']):
                raise ValueError('Recorded container identity changed')
        elif item['kind'] in ('network', 'volume'):
            if not _existing(item['kind'], item['name']):
                if item.get('status') == 'pending':
                    continue
                raise ValueError('Recorded resource is missing')
            current = js(item['kind'], 'inspect', item['name'])[0]
            if (current.get('Labels') or {}).get(TRANSACTION_LABEL) != transaction:
                raise ValueError('Recorded resource ownership changed')
        elif item['kind'] == 'bind':
            if item.get('status') == 'pending':
                target = Path(item['name'])
                if target.exists() and not _owned_bind(target, transaction):
                    raise ValueError('Pending bind exists without transaction marker')
            elif not _owned_bind(Path(item['name']), transaction):
                raise ValueError('Recorded bind ownership changed')
    journal['state'] = 'running'
    save_journal(path, journal)
    return _execute_restore(path, journal)


HELP_TEXT = """Docker 离线迁移

用法: fusionbox panels docker-migration <操作> [参数] [选项]

操作:
  export <bundle>      导出（--container 或 --compose-project 二选一）
  verify <bundle>      校验离线包完整性
  preflight <bundle>   只读目标兼容性与冲突预检
  restore <bundle>     恢复（--confirm-clean-target 清空目标）
  rollback <事务ID>    回滚
  resume <事务ID>      续跑中断的恢复

示例: fusionbox panels docker-migration preflight ./mybundle
"""


class _ChineseArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        print('参数有误: ' + message, file=sys.stderr)
        print(HELP_TEXT, file=sys.stderr)
        raise SystemExit(2)


def main(argv=None):
    os.umask(0o077)
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] in ('help', '--help', '-h'):
        print(HELP_TEXT)
        return
    parser = _ChineseArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    create = sub.add_parser('export')
    create.add_argument('bundle')
    group = create.add_mutually_exclusive_group(required=True)
    group.add_argument('--container', action='append', default=[])
    group.add_argument('--compose-project')
    create.add_argument('--bind', action='append', default=[], metavar='ABSOLUTE_SOURCE=LOGICAL')
    create.add_argument('--confirm-bind', action='append', default=[], metavar='ABSOLUTE_SOURCE')
    create.add_argument('--confirm-stop-writers', action='store_true',
                        help='Confirm all Docker and non-Docker writers are externally frozen; FusionBox only stops selected containers')
    check = sub.add_parser('verify')
    check.add_argument('bundle')
    before = sub.add_parser('preflight', help='Read-only target compatibility and conflict checks')
    before.add_argument('bundle')
    before.add_argument('--bind-target', action='append', default=[], metavar='LOGICAL=ABSOLUTE_TARGET')
    before.add_argument('--external-volume-policy', choices=('reject',), default='reject')
    apply = sub.add_parser('restore')
    apply.add_argument('bundle')
    apply.add_argument('--bind-target', action='append', default=[], metavar='LOGICAL=ABSOLUTE_TARGET')
    apply.add_argument('--external-volume-policy', choices=('reject',), default='reject')
    apply.add_argument('--confirm-clean-target', action='store_true')
    apply.add_argument('--health-timeout', type=int, default=120)
    undo = sub.add_parser('rollback')
    undo.add_argument('transaction')
    again = sub.add_parser('resume')
    again.add_argument('transaction')
    args = parser.parse_args(argv)
    if args.action == 'verify':
        declaration = inspect_bundle(args.bundle)
        print('Verified docker-v1 bundle:', declaration['selection']['kind'])
    elif args.action == 'preflight':
        declaration, targets = preflight(args.bundle, args.bind_target, args.external_volume_policy)
        print('Preflight passed (read-only):', len(declaration['containers']), 'containers,', len(targets), 'bind targets')
    elif args.action == 'restore':
        if not 1 <= args.health_timeout <= 3600:
            raise ValueError('--health-timeout must be 1..3600 seconds')
        journal = restore(args.bundle, args.bind_target, args.confirm_clean_target,
                          args.external_volume_policy, args.health_timeout)
        print('Restore complete. Transaction:', journal['transaction'])
    elif args.action == 'rollback':
        journal = rollback(args.transaction)
        print('Rollback complete. Transaction:', journal['transaction'])
    elif args.action == 'resume':
        journal = resume(args.transaction)
        print('Restore resumed. Transaction:', journal['transaction'], 'State:', journal['state'])
    else:
        declaration = export(args.bundle, args.container, args.compose_project, args.bind,
                             args.confirm_bind, args.confirm_stop_writers)
        print('Exported docker-v1 bundle:', args.bundle)
        print('Containers:', len(declaration['containers']), 'Images:', len(declaration['images']))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Docker migration failed:', error, file=sys.stderr)
        sys.exit(1)
