"""Credential-free node transfer; legacy nodes.conf remains the local storage format."""
import argparse
import contextlib
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

LIMIT = 1024 * 1024


def node(value):
    if not isinstance(value, dict) or set(value) != {'id', 'host', 'user', 'port'}:
        raise ValueError('Node requires exactly id, host, user, port; credentials are forbidden')
    for field, pattern in (('id', r'[A-Za-z0-9_][A-Za-z0-9_-]{0,63}'),
                           ('user', r'[A-Za-z_][A-Za-z0-9_-]{0,31}')):
        if not isinstance(value[field], str) or not re.fullmatch(pattern, value[field]):
            raise ValueError('Invalid node ' + field)
    host = value['host']
    if not isinstance(host, str) or not host or len(host) > 253 or '%' in host:
        raise ValueError('Invalid host')
    try:
        ipaddress.ip_address(host)
    except ValueError:
        if ':' in host or re.fullmatch(r'[0-9.]+', host) or any(
                not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', part)
                for part in host.split('.')):
            raise ValueError('Invalid hostname/IP (IPv6 must be bare, without zone ID)')
    if type(value['port']) is not int or not 1 <= value['port'] <= 65535:
        raise ValueError('Invalid port')
    return value


def unique(nodes):
    if not isinstance(nodes, list) or len(nodes) > 4096:
        raise ValueError('Invalid node list')
    seen = set()
    for item in nodes:
        node(item)
        if item['id'] in seen:
            raise ValueError('Duplicate node ID')
        seen.add(item['id'])
    return nodes


def safe(path, missing=False):
    path = Path(os.path.abspath(path))
    for parent in (*reversed(path.parents), path):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            if parent == path and missing:
                return path
            raise
        if stat.S_ISLNK(info.st_mode):
            raise ValueError('Symlink paths forbidden')
        if parent != path:
            if not stat.S_ISDIR(info.st_mode) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
                raise ValueError('Unsafe parent directory')
        elif not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid() or info.st_mode & 0o077:
            raise ValueError('File must be operator-owned, singly linked and private (0600/0400)')
    return path


def read(path):
    path = safe(path)
    with open(path, 'rb') as stream:
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError('Node file exceeds 1 MiB')
    return data.decode('utf-8')


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError('Duplicate JSON property')
        result[key] = value
    return result


def incoming(path):
    data = json.loads(read(path), object_pairs_hook=pairs)
    if not isinstance(data, dict) or set(data) != {'format', 'version', 'nodes'} or data['format'] != 'fusionbox-cluster-nodes' or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Unknown node transfer format/version')
    return unique(data['nodes'])


def legacy(path):
    if not safe(path, True).exists():
        return []
    result = []
    for line in read(path).splitlines():
        if not line:
            continue
        fields = line.split('|')
        if len(fields) != 3 or fields[1].count('@') != 1 or not re.fullmatch('[0-9]{1,5}', fields[2]):
            raise ValueError('Invalid legacy row; repair manually; file unchanged')
        user, host = fields[1].split('@')
        result.append({'id': fields[0], 'user': user, 'host': host, 'port': int(fields[2])})
    return unique(result)


def rows(nodes):
    return ''.join(f"{n['id']}|{n['user']}@{n['host']}|{n['port']}\n" for n in nodes)


def write(path, text, exclusive=False):
    if len(text.encode('utf-8')) > LIMIT:
        raise ValueError('Serialized node file exceeds 1 MiB')
    path = safe(path, True)
    fd, name = tempfile.mkstemp(prefix='.nodes-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        safe(path, True)
        if exclusive:
            os.link(name, path)  # atomic no-clobber publication
        else:
            os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextlib.contextmanager
def locked(base):
    base = Path(os.path.abspath(base))
    # Validate parents before creating the private registry directory.
    safe(base / '.parent-check', True) if base.exists() else safe(base, True)
    base.mkdir(mode=0o700, exist_ok=True)
    info = base.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
        raise ValueError('Unsafe cluster directory')
    lock = safe(base / '.nodes.lock', True)
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        safe(lock)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield base / 'nodes.conf'
    finally:
        os.close(fd)


def operate(base, action, file=None, confirm=False, item=None, name=None):
    with locked(base) as target:
        current = legacy(target)
        if action == 'list':
            print(rows(current), end='')
        elif action == 'export':
            write(file, json.dumps({'format': 'fusionbox-cluster-nodes', 'version': 1, 'nodes': current}, indent=2) + '\n', True)
            print('Exported credential-free nodes; mode 0600')
        elif action == 'import':
            additions = incoming(file)
            conflicts = {n['id'] for n in current} & {n['id'] for n in additions}
            for n in additions:
                print(('CONFLICT ' if n['id'] in conflicts else 'ADD ') + n['id'] + ' ' + n['user'] + '@' + n['host'] + ':' + str(n['port']))
            if conflicts:
                raise ValueError('Conflicting node IDs; no changes (even identical nodes are rejected)')
            merged = unique(current + additions)
            if confirm:
                write(target, rows(merged))
                print('Merge completed; existing nodes retained; no SSH connections made')
            else:
                print('Dry-run only; use --confirm to merge after review')
        elif action == 'add':
            write(target, rows(unique(current + [node(item)])))
        elif action == 'remove':
            if name not in {n['id'] for n in current}:
                raise ValueError('Unknown node ID')
            write(target, rows([n for n in current if n['id'] != name]))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--directory', default='/etc/fusionbox/cluster')
    sub = p.add_subparsers(dest='action', required=True)
    sub.add_parser('list')
    export = sub.add_parser('export'); export.add_argument('file')
    imp = sub.add_parser('import'); imp.add_argument('file')
    mode = imp.add_mutually_exclusive_group()
    mode.add_argument('--confirm', action='store_true'); mode.add_argument('--dry-run', action='store_true')
    add = sub.add_parser('add')
    for field in ('id', 'user', 'host'): add.add_argument(field)
    add.add_argument('port', type=int)
    remove = sub.add_parser('remove'); remove.add_argument('id')
    args = p.parse_args()
    operate(args.directory, args.action, getattr(args, 'file', None), getattr(args, 'confirm', False),
            {k: getattr(args, k) for k in ('id', 'user', 'host', 'port')} if args.action == 'add' else None,
            getattr(args, 'id', None))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print('Cluster nodes failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
