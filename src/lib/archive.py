"""Scoped offline backups. Stop writers before use; not a database snapshot."""
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile

SCOPES = {
    'config': ('etc/nginx', 'etc/caddy'),
    'system': ('etc/fusionbox', 'etc/nginx', 'etc/caddy', 'var/www', 'opt/docker'),
    'web': ('var/www', 'opt/docker', 'etc/nginx'),
}
MANIFEST = 'fusionbox-manifest.json'


def validate(archive, scope):
    members = archive.getmembers()
    names = set()
    for member in members:
        path = PurePosixPath(member.name)
        if (member.name in names or path.is_absolute() or '..' in path.parts
                or str(path) != member.name or not (member.isdir() or member.isfile())):
            raise ValueError('Unsafe or duplicate archive member: ' + member.name)
        names.add(member.name)
    manifest = archive.getmember(MANIFEST)
    if not manifest.isfile() or manifest.size > 16384:
        raise ValueError('Invalid manifest')
    data = json.load(archive.extractfile(manifest))
    roots = data.get('roots', [])
    if (data.get('format') != 1 or data.get('scope') != scope or not roots
            or len(roots) != len(set(roots)) or any(r not in SCOPES[scope] for r in roots)):
        raise ValueError('Invalid backup scope')
    for member in members:
        if member.name == MANIFEST:
            continue
        if not any(member.name == r or member.name.startswith(r + '/') for r in roots):
            raise ValueError('Out-of-scope archive member')
    for root in roots:
        if not archive.getmember(root).isdir():
            raise ValueError('Missing scope root')
    return roots


def create(destination, scope, root):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise ValueError('Backup already exists')
    roots = [r for r in SCOPES[scope] if (root / r).is_dir()]
    if not roots:
        raise ValueError('No backup sources')
    fd, temporary = tempfile.mkstemp(prefix='.fusionbox-archive-', dir=destination.parent)
    os.close(fd)
    try:
        import io
        with tarfile.open(temporary, 'w:gz', dereference=False) as archive:
            payload = json.dumps({'format': 1, 'scope': scope, 'roots': roots}).encode()
            info = tarfile.TarInfo(MANIFEST)
            info.size = len(payload)
            info.mode = 0o600
            archive.addfile(info, io.BytesIO(payload))
            for name in roots:
                archive.add(root / name, arcname=name)
        with tarfile.open(temporary, 'r:gz') as archive:
            validate(archive, scope)
            for member in archive.getmembers():
                if member.isfile():
                    with archive.extractfile(member) as source:
                        while source.read(1024 * 1024):
                            pass
        # Publish without overwriting an existing backup from a concurrent run.
        os.link(temporary, destination)
    finally:
        os.unlink(temporary)


def restore(source, scope, root):
    # No extractall: only checked directories and regular files are materialized.
    with tarfile.open(source, 'r:gz') as archive:
        roots = validate(archive, scope)
        for name in roots:
            target = root / name
            for parent in [target, *target.parents]:
                if parent.is_symlink():
                    raise ValueError('Refusing symlink destination')
            if target.exists() and not target.is_dir():
                raise ValueError('Destination is not a directory')
        staged = []
        activated = []
        try:
            for name in roots:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                txn = Path(tempfile.mkdtemp(prefix='.fusionbox-restore-', dir=target.parent))
                staged.append((target, txn))
                os.chmod(txn, 0o700)
                new = txn / 'new'
                new.mkdir()
                for member in archive.getmembers():
                    if member.name != name and not member.name.startswith(name + '/'):
                        continue
                    relative = PurePosixPath(member.name).relative_to(name)
                    path = new / str(relative)
                    if member.isdir():
                        path.mkdir(parents=True, exist_ok=True)
                    else:
                        path.parent.mkdir(parents=True, exist_ok=True)
                        with archive.extractfile(member) as src, path.open('xb') as dst:
                            shutil.copyfileobj(src, dst)
                    if hasattr(os, 'geteuid') and os.geteuid() == 0:
                        os.chown(path, member.uid, member.gid)
                    os.chmod(path, member.mode & 0o777)
                # Keep previous trees next to each target for manual recovery.
            for target, txn in staged:
                existed = target.exists()
                if existed:
                    target.rename(txn / 'previous')
                activated.append((target, txn, existed))
                (txn / 'new').rename(target)
            for target, txn in staged:
                print('Recovery directory:', txn)
        except BaseException:
            for target, txn, existed in reversed(activated):
                if target.exists():
                    target.rename(txn / 'failed')
                if existed:
                    (txn / 'previous').rename(target)
            raise
        finally:
            for target, txn in staged:
                if (txn / 'new').exists():
                    shutil.rmtree(txn / 'new')


def main():
    action, scope, filename = sys.argv[1:4]
    root = Path(sys.argv[4]) if len(sys.argv) > 4 else Path('/')
    if action == 'create':
        create(filename, scope, root)
    elif action == 'restore':
        restore(filename, scope, root)
    else:
        raise ValueError('Unknown action')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Backup operation failed:', error, file=sys.stderr)
        sys.exit(1)
