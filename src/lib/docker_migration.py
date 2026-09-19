"""Export and verify Docker migration bundles; callers must freeze all host writers."""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tarfile
import tempfile

OWNER = 'fusionbox-docker-migration-v1'
FORMAT = 1
MANIFEST = 'manifest.json'
DECLARATION = 'declaration.json'
NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}')
LOGICAL = re.compile(r'[a-z0-9][a-z0-9_-]{0,47}')


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
        'id': image['Id'], 'repo_digests': image.get('RepoDigests') or [],
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
        'network_mode': host.get('NetworkMode'), 'networks': networks,
        'labels': config.get('Labels') or {},
        'mounts': [{key: mount.get(key) for key in ('Type', 'Name', 'Source', 'Destination', 'Driver', 'Mode', 'RW', 'Propagation')}
                   for mount in container.get('Mounts') or []],
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
            with image_tar.open('xb') as stream:
                docker('image', 'save', *[item['id'] for item in declaration['images']], stdout=stream)
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
        required_declaration = {'format', 'owner', 'selection', 'engine', 'containers', 'images', 'networks', 'data'}
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
        if (not isinstance(declaration, dict) or set(declaration) != required_declaration
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
        current_ids = set(docker('ps', '-aq').decode().split())
        if not selected_ids.issubset(current_ids):
            raise RuntimeError('Docker topology changed after stop; refusing snapshot')
        package(destination, selected, volumes, mappings, declaration)
    return declaration


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
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
    args = parser.parse_args()
    if args.action == 'verify':
        declaration = inspect_bundle(args.bundle)
        print('Verified docker-v1 bundle:', declaration['selection']['kind'])
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
