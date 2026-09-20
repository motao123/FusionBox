"""Auditable scoped file backups. Stop writers before use; databases are excluded."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile

OWNER = 'fusionbox-system-backup-v2'
FORMAT = 2
MANIFEST = 'fusionbox-manifest.json'
SCOPES = {
    'config': ('etc/nginx', 'etc/caddy'),
    'fusion': ('etc/fusionbox',),
    'web': ('var/www', 'etc/nginx', 'etc/caddy'),
    'docker': ('opt/docker',),
    'ssh': ('etc/ssh',),
    'cron': ('etc/crontab', 'etc/cron.d', 'var/spool/cron'),
    'usr-local': ('usr/local',),
    'home': ('home',),
}
ALIASES = {'system': ('fusion', 'web', 'docker')}
SENSITIVE = frozenset(('ssh', 'cron', 'usr-local', 'home'))


def normalize_scopes(scopes):
    if isinstance(scopes, str):
        scopes = scopes.split(',')
    result = []
    for value in scopes:
        name = value.strip()
        if not name:
            continue
        for scope in ALIASES.get(name, (name,)):
            if scope not in SCOPES:
                raise ValueError('Unknown backup scope: ' + scope)
            if scope not in result:
                result.append(scope)
    if not result:
        raise ValueError('At least one backup scope is required')
    return result


def _inside(root, relative):
    path = root / relative
    if path == root or root not in path.parents:
        raise ValueError('Backup path escapes root: ' + relative)
    return path


def _digest(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(block)
    return result.hexdigest()


def _entry(path, name, info):
    record = {'path': name, 'type': 'directory' if stat.S_ISDIR(info.st_mode) else 'file',
              'owner': {'uid': info.st_uid, 'gid': info.st_gid},
              'mode': info.st_mode & 0o7777}
    if record['type'] == 'file':
        with path.open('rb') as stream:
            record['sha256'] = _digest(stream)
        record['size'] = info.st_size
    return record


def audit(root, scopes, required=True):
    """Return regular files/directories without following links or crossing devices.

    ``required=False`` allows scopes whose sources are absent to be skipped (and
    reported) instead of aborting the whole backup, which is what a fresh host
    needs for the default scope set.
    """
    root = Path(root).absolute()
    selected = normalize_scopes(scopes)
    entries = []
    roots = []
    seen_roots = set()
    scope_roots = {}
    skipped = []
    for scope in selected:
        found = []
        for relative in SCOPES[scope]:
            if relative in seen_roots:
                found.append(relative)
                continue
            path = _inside(root, relative)
            try:
                info = path.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(info.st_mode) or not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                raise ValueError('Refusing link or special backup source: ' + relative)
            roots.append(relative)
            found.append(relative)
            seen_roots.add(relative)
            entries.append(_entry(path, relative, info))
            if stat.S_ISDIR(info.st_mode):
                device = info.st_dev
                for current, directories, files in os.walk(path, topdown=True, followlinks=False):
                    directories.sort()
                    files.sort()
                    current_path = Path(current)
                    for child_name in directories + files:
                        child = current_path / child_name
                        child_info = child.lstat()
                        archive_name = child.relative_to(root).as_posix()
                        if stat.S_ISLNK(child_info.st_mode):
                            raise ValueError('Refusing symlink backup source: ' + archive_name)
                        if child_info.st_dev != device:
                            raise ValueError('Refusing filesystem boundary: ' + archive_name)
                        if not (stat.S_ISDIR(child_info.st_mode) or stat.S_ISREG(child_info.st_mode)):
                            raise ValueError('Refusing special backup source: ' + archive_name)
                        entries.append(_entry(child, archive_name, child_info))
        if not found:
            if required:
                raise ValueError('No backup sources for scope: ' + scope)
            # A scope whose sources do not exist on this host is skipped and
            # reported, instead of failing the whole backup on a fresh machine.
            skipped.append(scope)
            print('已跳过 scope ' + scope + '（' + ', '.join(
                str(Path('/') / relative) for relative in SCOPES[scope]) + ' 均不存在）',
                file=sys.stderr)
            continue
        scope_roots[scope] = found
    if not scope_roots:
        raise ValueError('没有任何可备份范围（已跳过: ' + ','.join(skipped) + '）；'
                         '请先安装 FusionBox 部署，或用 --scope 显式指定存在的范围')
    return {'format': FORMAT, 'owner': OWNER, 'scopes': [s for s in selected if s in scope_roots],
            'scope_roots': scope_roots, 'skipped_scopes': skipped,
            'roots': roots, 'entries': entries,
            'database_consistency': 'excluded; use application-native database dumps separately'}


def _manifest(archive, expected_scopes=None):
    members = archive.getmembers()
    names = set()
    for member in members:
        path = PurePosixPath(member.name)
        if (member.name in names or path.is_absolute() or '..' in path.parts
                or str(path) != member.name or not (member.isdir() or member.isfile())):
            raise ValueError('Unsafe or duplicate archive member: ' + member.name)
        names.add(member.name)
    try:
        member = archive.getmember(MANIFEST)
    except KeyError:
        raise ValueError('Missing manifest') from None
    if not member.isfile() or member.size > 64 * 1024 * 1024:
        raise ValueError('Invalid manifest')
    data = json.load(archive.extractfile(member))
    if data.get('format') == 1:
        legacy_scope = data.get('scope')
        legacy_map = {
            'config': ('config',),
            'web': ('web', 'docker'),
            'system': ('fusion', 'web', 'docker'),
        }
        if legacy_scope not in legacy_map:
            raise ValueError('Invalid legacy backup scope')
        roots = data.get('roots')
        if (not isinstance(roots, list) or not roots or len(roots) != len(set(roots))
                or any(root not in ('etc/fusionbox', 'etc/nginx', 'etc/caddy', 'var/www', 'opt/docker') for root in roots)):
            raise ValueError('Invalid legacy backup roots')
        scopes = list(legacy_map[legacy_scope])
        scope_roots = {scope: [root for root in roots if root in SCOPES[scope]] for scope in scopes}
        scope_roots = {scope: values for scope, values in scope_roots.items() if values}
        scopes = list(scope_roots)
        entries = []
        for legacy_member in members:
            if legacy_member.name == MANIFEST:
                continue
            record = {
                'path': legacy_member.name,
                'type': 'directory' if legacy_member.isdir() else 'file',
                'owner': {'uid': legacy_member.uid, 'gid': legacy_member.gid},
                'mode': legacy_member.mode & 0o7777,
            }
            if legacy_member.isfile():
                record['size'] = legacy_member.size
                record['sha256'] = _digest(archive.extractfile(legacy_member))
            entries.append(record)
        data = {'format': FORMAT, 'owner': OWNER, 'scopes': scopes, 'scope_roots': scope_roots,
                'roots': roots, 'entries': entries,
                'database_consistency': 'legacy format 1; no original per-file checksums'}
    scopes = normalize_scopes(data.get('scopes', []))
    if (data.get('format') != FORMAT or data.get('owner') != OWNER
            or scopes != data.get('scopes') or data.get('database_consistency') is None):
        raise ValueError('Invalid manifest ownership or format')
    if expected_scopes is not None:
        requested = normalize_scopes(expected_scopes)
        if any(scope not in scopes for scope in requested):
            raise ValueError('Requested scope is not present in backup')
    roots = data.get('roots')
    scope_roots = data.get('scope_roots')
    entries = data.get('entries')
    if not isinstance(roots, list) or not roots or len(roots) != len(set(roots)):
        raise ValueError('Invalid manifest roots')
    if not isinstance(scope_roots, dict) or set(scope_roots) != set(scopes):
        raise ValueError('Invalid manifest scope roots')
    allowed = {name for scope in scopes for name in SCOPES[scope]}
    if any(root not in allowed for root in roots):
        raise ValueError('Out-of-scope manifest root')
    for scope, values in scope_roots.items():
        if (not isinstance(values, list) or not values
                or any(value not in SCOPES[scope] or value not in roots for value in values)):
            raise ValueError('Invalid roots for scope: ' + scope)
    if not isinstance(entries, list) or len(entries) != len(names) - 1:
        raise ValueError('Invalid manifest entries')
    records = {}
    for record in entries:
        if not isinstance(record, dict) or record.get('path') in records:
            raise ValueError('Invalid manifest entry')
        name = record.get('path')
        if name not in names or name == MANIFEST or record.get('type') not in ('file', 'directory'):
            raise ValueError('Manifest member mismatch')
        if not isinstance(record.get('owner'), dict) or set(record['owner']) != {'uid', 'gid'}:
            raise ValueError('Invalid manifest owner')
        if not all(isinstance(record['owner'][key], int) and record['owner'][key] >= 0 for key in ('uid', 'gid')):
            raise ValueError('Invalid manifest owner')
        if not isinstance(record.get('mode'), int) or record['mode'] < 0 or record['mode'] > 0o7777:
            raise ValueError('Invalid manifest mode')
        tar_member = archive.getmember(name)
        if record['type'] == 'directory' and not tar_member.isdir():
            raise ValueError('Manifest type mismatch')
        if record['type'] == 'file':
            if not tar_member.isfile() or record.get('size') != tar_member.size:
                raise ValueError('Manifest file mismatch')
            if not isinstance(record.get('sha256'), str) or len(record['sha256']) != 64:
                raise ValueError('Invalid manifest hash')
        if not any(name == root or name.startswith(root + '/') for root in roots):
            raise ValueError('Out-of-scope manifest member')
        records[name] = record
    if set(records) != names - {MANIFEST}:
        raise ValueError('Archive member missing from manifest')
    for root in roots:
        if root not in records:
            raise ValueError('Missing scope root')
    return data, records


def validate(archive, scopes=None):
    data, _ = _manifest(archive, scopes)
    return data['roots']


def create(destination, scopes, root, allow_skip=True):
    destination = Path(destination)
    root = Path(root).absolute()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Backup already exists')
    data = audit(root, scopes, required=not allow_skip)
    fd, temporary = tempfile.mkstemp(prefix='.fusionbox-archive-', dir=destination.parent)
    os.close(fd)
    try:
        with tarfile.open(temporary, 'w:gz', dereference=False) as archive:
            payload = json.dumps(data, sort_keys=True, separators=(',', ':')).encode()
            info = tarfile.TarInfo(MANIFEST)
            info.size, info.mode = len(payload), 0o600
            archive.addfile(info, io.BytesIO(payload))
            for record in data['entries']:
                source = _inside(root, record['path'])
                current = source.lstat()
                if (current.st_uid != record['owner']['uid'] or current.st_gid != record['owner']['gid']
                        or current.st_mode & 0o7777 != record['mode']
                        or ('size' in record and current.st_size != record['size'])):
                    raise ValueError('Backup source changed during snapshot: ' + record['path'])
                info = archive.gettarinfo(str(source), record['path'])
                if record['type'] == 'file':
                    with source.open('rb') as stream:
                        archive.addfile(info, stream)
                else:
                    archive.addfile(info)
        verify(temporary, data['scopes'])
        os.chmod(temporary, 0o600)
        os.link(temporary, destination)
    finally:
        os.unlink(temporary)
    return data


def inspect(source, scopes=None):
    import gzip
    with gzip.open(source, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
    with tarfile.open(source, 'r:gz') as archive:
        data, records = _manifest(archive, scopes)
        for name, record in records.items():
            if record['type'] == 'file':
                with archive.extractfile(name) as stream:
                    if _digest(stream) != record['sha256']:
                        raise ValueError('Archive member checksum mismatch: ' + name)
    return data


def verify(source, scopes=None):
    return inspect(source, scopes)['roots']


def preview(source, scopes, root, conflict='abort'):
    if conflict not in ('abort', 'replace', 'skip'):
        raise ValueError('Conflict policy must be abort, replace or skip')
    root = Path(root).absolute()
    data = inspect(source, scopes)
    selected = normalize_scopes(scopes)
    roots = []
    for scope in selected:
        for name in data['scope_roots'][scope]:
            if name not in roots:
                roots.append(name)
    result = []
    for name in roots:
        target = _inside(root, name)
        for parent in (target, *target.parents):
            if parent.is_symlink():
                raise ValueError('Refusing symlink destination: ' + str(target))
            if parent == root:
                break
        exists = target.exists()
        action = 'skip' if exists and conflict == 'skip' else 'replace' if exists else 'create'
        result.append({'root': name, 'scope': [s for s in selected if name in data['scope_roots'][s]],
                       'state': 'present' if exists else 'absent', 'action': action})
    if conflict == 'abort' and any(item['state'] == 'present' for item in result):
        raise ValueError('Restore conflicts found; choose replace or skip after preview')
    return result


def _metadata(path, record):
    if hasattr(os, 'geteuid') and os.geteuid() == 0:
        os.chown(path, record['owner']['uid'], record['owner']['gid'])
    os.chmod(path, record['mode'])


def restore(source, scopes, root, conflict='abort'):
    plan = preview(source, scopes, root, conflict)
    source = Path(source)
    root = Path(root).absolute()
    with source.open('rb') as raw:
        with tarfile.open(fileobj=raw, mode='r:gz') as archive:
            _, records = _manifest(archive, scopes)
            staged = []
            activated = []
            try:
                for item in plan:
                    if item['action'] == 'skip':
                        continue
                    name = item['root']
                    target = _inside(root, name)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    txn = Path(tempfile.mkdtemp(prefix='.fusionbox-restore-', dir=target.parent))
                    os.chmod(txn, 0o700)
                    new = txn / 'new'
                    root_record = records[name]
                    if root_record['type'] == 'directory':
                        new.mkdir()
                    staged.append((target, txn))
                    members = [m for m in archive.getmembers() if m.name == name or m.name.startswith(name + '/')]
                    directories = []
                    for member in members:
                        record = records[member.name]
                        relative = PurePosixPath(member.name).relative_to(name)
                        path = new if str(relative) == '.' else new / str(relative)
                        if record['type'] == 'directory':
                            path.mkdir(parents=True, exist_ok=True)
                            directories.append((path, record))
                        else:
                            path.parent.mkdir(parents=True, exist_ok=True)
                            with archive.extractfile(member) as src, path.open('xb') as dst:
                                shutil.copyfileobj(src, dst)
                            with path.open('rb') as restored:
                                if _digest(restored) != record['sha256']:
                                    raise ValueError('Archive member changed during restore: ' + member.name)
                            _metadata(path, record)
                    for path, record in reversed(directories):
                        _metadata(path, record)
                for target, txn in staged:
                    existed = target.exists()
                    if existed:
                        target.rename(txn / 'previous')
                    activated.append((target, txn, existed))
                    (txn / 'new').rename(target)
                for target, txn in staged:
                    print('Restore:', target, 'recovery directory:', txn)
            except BaseException:
                rollback_errors = []
                for target, txn, existed in reversed(activated):
                    try:
                        if target.exists():
                            target.rename(txn / 'failed')
                        if existed:
                            (txn / 'previous').rename(target)
                    except BaseException as error:
                        rollback_errors.append(str(error))
                if rollback_errors:
                    raise RuntimeError('Restore and rollback failed; recovery directories retained: ' + '; '.join(rollback_errors)) from None
                raise
            finally:
                for _, txn in staged:
                    pending = txn / 'new'
                    if pending.exists():
                        shutil.rmtree(pending) if pending.is_dir() else pending.unlink()
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('create', 'verify', 'preview', 'restore'))
    parser.add_argument('scopes', help='Comma-separated explicit scopes: ' + ','.join(SCOPES))
    parser.add_argument('filename')
    parser.add_argument('legacy_root', nargs='?', help=argparse.SUPPRESS)
    parser.add_argument('--root', default=None)
    parser.add_argument('--conflict', choices=('abort', 'replace', 'skip'), default='abort')
    parser.add_argument('--require-all-scopes', action='store_true',
                        help='Fail when a scope has no sources instead of skipping it')
    args = parser.parse_args()
    if args.root is not None and args.legacy_root is not None:
        parser.error('choose either legacy positional root or --root')
    root = Path(args.root or args.legacy_root or '/')
    scopes = normalize_scopes(args.scopes)
    if args.action == 'create':
        data = create(args.filename, scopes, root, allow_skip=not args.require_all_scopes)
        print('Created scopes:', ', '.join(data['scopes']))
        for scope in data.get('skipped_scopes', []):
            print('Skipped scope (no sources):', scope)
    elif args.action == 'verify':
        data = inspect(args.filename, scopes)
        print('Verified scopes:', ', '.join(data['scopes']))
        print('Database consistency:', data['database_consistency'])
    elif args.action == 'preview':
        for item in preview(args.filename, scopes, root, args.conflict):
            print(item['action'].upper(), item['root'], '[' + ','.join(item['scope']) + ']', item['state'])
    else:
        restore(args.filename, scopes, root, args.conflict)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Backup operation failed:', error, file=sys.stderr)
        sys.exit(1)
