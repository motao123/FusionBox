"""Opt-in local Compose snapshots. Private metadata may contain secrets; never print it."""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from backup_jobs import atomic

BASE = Path('/var/lib/fusionbox/compose-projects')
OWNER = 'fusionbox-compose-v1'


def docker(*args):
    # Never accept an environment-selected remote daemon or alternate socket.
    if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'):
        raise ValueError('Remote/alternate Docker endpoints unsupported')
    result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', *args],
                            capture_output=True)
    if result.returncode:
        raise RuntimeError('Docker operation failed (output withheld to protect secrets)')
    return result.stdout


def js(*args):
    return json.loads(docker(*args))


def no_links(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Symlink path unsupported')


@contextlib.contextmanager
def lock(project):
    import fcntl
    if not re.fullmatch('[a-z0-9][a-z0-9_-]{0,47}', project):
        raise ValueError('Invalid project identity')
    no_links(BASE)
    BASE.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(BASE, 0o700)
    # Global registry lock also prevents two registered projects operating concurrently.
    fd = os.open(BASE / '.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another Compose operation is active')
        yield BASE / (project + '.json')


def config(record):
    path = Path(record['compose'])
    no_links(path)
    if not path.is_file() or str(path.resolve()) != record['compose']:
        raise ValueError('Compose source moved or unavailable')
    data = js('compose', '-p', record['project'], '-f', str(path), 'config', '--format', 'json')
    services = data.get('services', {})
    if not services:
        raise ValueError('No services')
    for service in services.values():
        if service.get('volumes_from') or service.get('devices') or service.get('privileged') or service.get('configs') or service.get('secrets') or service.get('tmpfs'):
            raise ValueError('Unsupported service storage or privileges')
        for mount in service.get('volumes', []):
            if mount.get('type') != 'volume' or not mount.get('source') or mount.get('volume', {}).get('subpath'):
                raise ValueError('Only named volume mounts supported')
    for volume in data.get('volumes', {}).values():
        if volume.get('external') or volume.get('driver', 'local') != 'local' or volume.get('driver_opts'):
            raise ValueError('External or nonlocal volume unsupported')
    return data


def inspect(record):
    data = config(record)
    project = record['project']
    ids = docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).decode().split()
    if not ids:
        raise ValueError('Project must already be created')
    containers = js('inspect', *ids)
    root = Path(js('info', '--format', '{{json .DockerRootDir}}'))
    paths = {}
    for logical, definition in data.get('volumes', {}).items():
        name = definition.get('name')
        if not name or not re.fullmatch('[A-Za-z0-9][A-Za-z0-9_.-]+', name):
            raise ValueError('Invalid actual volume identity')
        volume = js('volume', 'inspect', name)[0]
        labels = volume.get('Labels') or {}
        if (volume['Driver'] != 'local' or volume.get('Options') or
                labels.get('com.docker.compose.project') != project or
                labels.get('com.docker.compose.volume') != logical):
            raise ValueError('Volume ownership/driver mismatch')
        path = Path(volume['Mountpoint'])
        if path != root / 'volumes' / name / '_data':
            raise ValueError('Unsupported volume mountpoint')
        no_links(path)
        if not path.is_dir():
            raise ValueError('Volume data unavailable locally')
        users = docker('ps', '-aq', '--filter', 'volume=' + name).decode().split()
        if set(users) - set(ids):
            raise ValueError('Volume shared outside registered project')
        paths[name] = path
    for container in containers:
        labels = container['Config'].get('Labels') or {}
        if (labels.get('com.docker.compose.service') not in data['services'] or
                labels.get('com.docker.compose.project.config_files') != record['compose'] or
                labels.get('com.docker.compose.oneoff', 'False').lower() == 'true'):
            raise ValueError('Container Compose identity mismatch')
        if container['HostConfig'].get('AutoRemove'):
            raise ValueError('Auto-remove container unsupported')
        if container['State'].get('Paused') or container['State'].get('Restarting'):
            raise ValueError('Paused/restarting containers unsupported')
        for mount in container.get('Mounts', []):
            if mount['Type'] != 'volume' or mount.get('Name') not in paths:
                raise ValueError('Bind/anonymous/unregistered mount unsupported')
    if not paths:
        raise ValueError('Project has no named data volumes')
    source = Path(record['compose'])
    if any(source == p or p in source.parents or BASE == p or p in BASE.parents for p in paths.values()):
        raise ValueError('Compose source/registry cannot reside inside managed volumes')
    return data, containers, paths


def register(project, compose, accepted):
    if not accepted:
        raise ValueError('Explicit project ownership/import confirmation required')
    path = Path(compose).absolute()
    no_links(path)
    record = {'owner': OWNER, 'project': project, 'compose': str(path.resolve())}
    with lock(project) as destination:
        if destination.exists() or destination.is_symlink():
            raise ValueError('Project already registered')
        inspect(record)
        atomic(destination, json.dumps(record) + '\n')
    print('Registered project:', project)


def load(path, project):
    no_links(path)
    record = json.loads(path.read_text())
    if record.get('owner') != OWNER or record.get('project') != project:
        raise ValueError('Unknown registry ownership')
    return record


@contextlib.contextmanager
def stopped(containers):
    running = [c['Id'] for c in containers if c['State']['Running']]
    recovery = {'restart_safe': True}
    try:
        # finally also covers partially successful stop commands.
        for identity in running:
            docker('stop', identity)
        # A successful stop command alone is insufficient if another actor restarts it.
        if running and any(c['State']['Running'] for c in js('inspect', *running)):
            raise RuntimeError('Project writers did not remain stopped')
        yield recovery
    finally:
        failures = []
        for identity in running if recovery['restart_safe'] else []:
            try:
                docker('start', identity)
            except Exception:
                failures.append(identity)
        if failures:
            raise RuntimeError(f'Original container restart failed for {len(failures)} of {len(running)} containers; project may be partially running; manual intervention required; inspect registry safety archives after restore')


def sha(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(block)
    return result.hexdigest()


def package(destination, record, data, containers, paths):
    destination = Path(destination)
    no_links(destination)
    if destination.exists():
        raise ValueError('Backup destination exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.compose-', dir=destination.parent)
    os.close(fd)
    try:
        with tarfile.open(name, 'w:gz', dereference=False) as out:
            payloads = {'compose.yaml': Path(record['compose']).read_bytes(),
                        'metadata.json': json.dumps({'record': record, 'resolved': data, 'containers': containers}).encode()}
            for member, payload in payloads.items():
                info = tarfile.TarInfo(member)
                info.size, info.mode = len(payload), 0o600
                out.addfile(info, io.BytesIO(payload))
            for volume, path in paths.items():
                out.add(path, arcname='volumes/' + volume)
        with tarfile.open(name, 'r:gz') as source:
            hashes = {m.name: sha(source.extractfile(m)) for m in source.getmembers() if m.isfile()}
        # Repack with manifest; only private temporary paths are used.
        with tempfile.TemporaryDirectory(prefix='.compose-manifest-', dir=destination.parent) as stage:
            final = Path(stage) / 'archive'
            with tarfile.open(name, 'r:gz') as source, tarfile.open(final, 'w:gz') as out:
                for member in source.getmembers():
                    out.addfile(member, source.extractfile(member) if member.isfile() else None)
                payload = json.dumps({'owner': OWNER, 'sha256': hashes}).encode()
                info = tarfile.TarInfo('manifest.json')
                info.size, info.mode = len(payload), 0o600
                out.addfile(info, io.BytesIO(payload))
            os.chmod(final, 0o600)
            verify(final, record, data, paths)
            os.link(final, destination)
    finally:
        os.unlink(name)


def verify(source, record, data, paths):
    import gzip
    with gzip.open(source, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
    with tarfile.open(source, 'r:gz') as archive:
        names = set()
        for member in archive.getmembers():
            p = PurePosixPath(member.name)
            if (str(p) != member.name or p.is_absolute() or '..' in p.parts or
                    member.name in names or not (member.isfile() or member.isdir())):
                raise ValueError('Unsafe archive member')
            names.add(member.name)
            if member.name not in ('compose.yaml', 'metadata.json', 'manifest.json'):
                if not any(member.name == 'volumes/' + n or member.name.startswith('volumes/' + n + '/') for n in paths):
                    raise ValueError('Unknown archive volume')
        manifest = json.load(archive.extractfile('manifest.json'))
        if manifest.get('owner') != OWNER:
            raise ValueError('Unknown manifest')
        actual = {m.name: sha(archive.extractfile(m)) for m in archive.getmembers() if m.isfile() and m.name != 'manifest.json'}
        if actual != manifest.get('sha256'):
            raise ValueError('Archive checksum mismatch')
        metadata = json.load(archive.extractfile('metadata.json'))
        if metadata['record'] != record or metadata['resolved'] != data:
            raise ValueError('Restore requires unchanged registered project/configuration')
        if archive.extractfile('compose.yaml').read() != Path(record['compose']).read_bytes():
            raise ValueError('Compose source changed since backup')
        for name in paths:
            if not archive.getmember('volumes/' + name).isdir():
                raise ValueError('Missing volume root')
    return True


def apply(source, paths):
    # Called only with a verified, private copy and stopped registered writers.
    with tarfile.open(source, 'r:gz') as archive:
        for name, target in paths.items():
            for child in target.iterdir():
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            prefix = 'volumes/' + name
            directories = []
            for member in archive.getmembers():
                if member.name != prefix and not member.name.startswith(prefix + '/'):
                    continue
                path = target / str(PurePosixPath(member.name).relative_to(prefix))
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                    directories.append((path, member))
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as src, path.open('xb') as dst:
                        shutil.copyfileobj(src, dst)
                    os.chown(path, member.uid, member.gid)
                    os.chmod(path, member.mode & 0o777)
            for path, member in reversed(directories):
                os.chown(path, member.uid, member.gid)
                os.chmod(path, member.mode & 0o777)


def operate(project, action, filename, accepted):
    if not accepted:
        raise ValueError('Explicit downtime and stopped external writers confirmation required')
    with lock(project) as registry:
        record = load(registry, project)
        data, containers, paths = inspect(record)
        destination = Path(filename).absolute()
        no_links(destination)
        if any(destination == p or p in destination.parents for p in paths.values()):
            raise ValueError('Archive cannot reside inside managed volume')
        if action == 'backup':
            with stopped(containers):
                package(filename, record, data, containers, paths)
        else:
            # Freeze the input before verification to prevent changing an archive mid-restore.
            with tempfile.TemporaryDirectory(prefix='.restore-', dir=BASE) as stage:
                source = Path(stage) / 'input.tar.gz'
                shutil.copyfile(filename, source)
                verify(source, record, data, paths)
                safety = BASE / (project + '-safety-' + Path(stage).name + '.tar.gz')
                with stopped(containers) as recovery:
                    package(safety, record, data, containers, paths)
                    print('Safety archive retained:', safety)
                    recovery['restart_safe'] = False
                    try:
                        apply(source, paths)
                    except BaseException:
                        try:
                            apply(safety, paths)
                        except BaseException:
                            raise RuntimeError('Restore AND rollback failed; project left stopped; manual intervention required; safety archive retained: ' + str(safety)) from None
                        recovery['restart_safe'] = True
                        raise RuntimeError('Restore failed; original data rolled back; safety archive retained: ' + str(safety)) from None
                    recovery['restart_safe'] = True
        print(action.capitalize() + ' completed; original running state restored')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('register', 'backup', 'restore'))
    parser.add_argument('project')
    parser.add_argument('path', help='Compose file for register; archive path otherwise')
    parser.add_argument('--confirm-owned-import', action='store_true')
    parser.add_argument('--confirm-stop-writers', action='store_true')
    args = parser.parse_args()
    if args.action == 'register':
        register(args.project, args.path, args.confirm_owned_import)
    else:
        operate(args.project, args.action, args.path, args.confirm_stop_writers)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Compose operation failed:', error, file=sys.stderr)
        sys.exit(1)
