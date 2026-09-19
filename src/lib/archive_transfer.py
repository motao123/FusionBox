"""Verified key-only SSH transfer of scoped archives; never extracts or deletes sources."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile

import archive
import cluster_nodes

# Sent as fixed program text, with separately shell-quoted arguments. Remote Python
# needs only its standard library; no installed FusionBox or sourced configuration.
REMOTE = r'''
import hashlib, os, re, signal, stat, sys, tempfile

def digest(stream):
    h = hashlib.sha256()
    for block in iter(lambda: stream.read(1048576), b''):
        h.update(block)
    return h.hexdigest()

def directory(root):
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', root) or any(p in ('', '.', '..') for p in root.split('/')[1:]):
        raise ValueError('Noncanonical store path')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        parts = root.split('/')[1:]
        for i, part in enumerate(parts):
            new = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = new
            info = os.fstat(fd)
            if info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX:
                raise ValueError('Writable store ancestor')
            if i == len(parts)-1 and (info.st_uid != os.geteuid() or info.st_mode & 0o077):
                raise ValueError('Store must be owned by SSH user with mode 0700')
        return fd
    except BaseException:
        os.close(fd)
        raise

def opened(fd, name):
    f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    info = os.fstat(f)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077 or info.st_nlink != 1:
        os.close(f)
        raise ValueError('Archive must be private, owned, regular and singly linked')
    return os.fdopen(f, 'rb')

def publish(fd, temporary, name, expected):
    try:
        # Atomic no-clobber publication; rename would overwrite a concurrent file.
        os.link(temporary, name, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False)
        os.fsync(fd)
    except FileExistsError:
        with opened(fd, name) as current:
            if digest(current) != expected:
                raise ValueError('Conflicting destination; unchanged')

def transfer(action, root, name, expected, size, timeout):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\.tar\.gz', name):
        raise ValueError('Invalid archive name')
    if not re.fullmatch('[a-f0-9]{64}', expected):
        raise ValueError('Invalid SHA256')
    def expired(*unused):
        raise TimeoutError('Transfer deadline exceeded')
    signal.signal(signal.SIGALRM, expired)
    signal.signal(signal.SIGHUP, expired)
    signal.signal(signal.SIGTERM, expired)
    signal.alarm(int(timeout))
    fd = directory(root)
    temporary = None
    try:
        if action == 'push':
            temporary = '.transfer-' + os.urandom(16).hex()
            out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
            remaining = int(size)
            if remaining < 0:
                raise ValueError('Invalid size')
            with os.fdopen(out, 'wb') as stream:
                while remaining:
                    block = sys.stdin.buffer.read(min(1048576, remaining))
                    if not block:
                        raise ValueError('Partial transfer')
                    stream.write(block)
                    remaining -= len(block)
                if sys.stdin.buffer.read(1):
                    raise ValueError('Excess transfer data')
                stream.flush()
                os.fsync(stream.fileno())
            with opened(fd, temporary) as stream:
                if digest(stream) != expected:
                    raise ValueError('Checksum mismatch')
            publish(fd, temporary, name, expected)
        else:
            with opened(fd, name) as stream:
                if digest(stream) != expected:
                    raise ValueError('Checksum mismatch')
                if action == 'pull':
                    stream.seek(0)
                    for block in iter(lambda: stream.read(1048576), b''):
                        sys.stdout.buffer.write(block)
                    sys.stdout.buffer.flush()
    finally:
        if temporary is not None:
            os.unlink(temporary, dir_fd=fd)
        os.close(fd)
        signal.alarm(0)
'''

# Use identical storage rules locally and remotely.
exec(REMOTE, globals())


def ssh_command(node, key, hosts, command):
    cluster_nodes.node(node)
    key = cluster_nodes.safe(key)
    hosts = cluster_nodes.safe(hosts)
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(hosts)):
        raise ValueError('known_hosts path must not contain whitespace or SSH option quoting')
    return ['ssh', '-F', '/dev/null', '-T', '-i', str(key),
            '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
            '-o', 'PasswordAuthentication=no', '-o', 'KbdInteractiveAuthentication=no',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile=' + str(hosts),
            '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'UpdateHostKeys=no',
            '-o', 'ConnectTimeout=10', '-o', 'ConnectionAttempts=1',
            '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=2',
            '-o', 'ClearAllForwardings=yes', '-p', str(node['port']),
            '-l', node['user'], '--', node['host'], command]


def run(args):
    if not args.confirm_owned_store:
        raise ValueError('Explicit --confirm-owned-store required; provision a dedicated 0700 directory first')
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', args.remote_root) or any(p in ('', '.', '..') for p in args.remote_root.split('/')[1:]):
        raise ValueError('Invalid remote root')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\.tar\.gz', args.name):
        raise ValueError('Invalid archive name')
    if not re.fullmatch('[a-f0-9]{64}', args.sha256):
        raise ValueError('Expected lowercase SHA256 required from a trusted source')
    if not 1 <= args.timeout <= 3600:
        raise ValueError('Timeout must be 1..3600 seconds')
    with cluster_nodes.locked(args.directory) as inventory:
        nodes = [n for n in cluster_nodes.legacy(inventory) if n['id'] == args.node]
    if len(nodes) != 1:
        raise ValueError('Unknown node')
    with tempfile.TemporaryDirectory(prefix='fusionbox-transfer-') as staging:
        frozen = Path(staging) / 'archive'
        local = Path(args.file).absolute() if args.file else None
        size = 0
        if args.action == 'push':
            source = cluster_nodes.safe(local)
            with source.open('rb') as src, frozen.open('xb') as dst:
                shutil.copyfileobj(src, dst)
            os.chmod(frozen, 0o600)
            archive.verify(frozen, args.scope)
            with frozen.open('rb') as stream:
                if digest(stream) != args.sha256:
                    raise ValueError('Local checksum mismatch')
            size = frozen.stat().st_size
        code = REMOTE + '\ntry:\n    transfer(*sys.argv[1:])\nexcept Exception:\n    print("Remote archive operation failed", file=sys.stderr)\n    sys.exit(1)\n'
        command = shlex.join(['python3', '-c', code, args.action, args.remote_root,
                              args.name, args.sha256, str(size), str(args.timeout)])
        argv = ssh_command(nodes[0], args.key, args.known_hosts, command)
        fd = None
        temporary = None
        try:
            if args.action == 'pull':
                fd = directory(str(local.parent))
                temporary = '.transfer-' + os.urandom(16).hex()
                out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
                with os.fdopen(out, 'wb') as stream:
                    result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=stream,
                                            stderr=subprocess.DEVNULL, timeout=args.timeout + 15)
                    stream.flush()
                    os.fsync(stream.fileno())
                # Verify through the pinned directory, never extract.
                candidate = f'/proc/self/fd/{fd}/{temporary}'
                with opened(fd, temporary) as stream:
                    if digest(stream) != args.sha256:
                        raise ValueError('Downloaded checksum mismatch')
                archive.verify(candidate, args.scope)
                if result.returncode:
                    raise RuntimeError('SSH transfer failed; source retained')
                publish(fd, temporary, local.name, args.sha256)
            else:
                with frozen.open('rb') if args.action == 'push' else open(os.devnull, 'rb') as stream:
                    result = subprocess.run(argv, stdin=stream, stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL, timeout=args.timeout + 15)
                if result.returncode:
                    raise RuntimeError('SSH operation failed; source retained (check host trust, permissions and hash)')
        finally:
            if temporary is not None:
                os.unlink(temporary, dir_fd=fd)
            if fd is not None:
                os.close(fd)
    print(args.action + ' verified: ' + args.sha256 + '; source retained; no extraction')


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('push', 'pull', 'status'))
    p.add_argument('node')
    p.add_argument('name', help='Remote archive basename ending .tar.gz')
    p.add_argument('--file', help='Local source/destination; private owned regular file for push')
    p.add_argument('--scope', required=True,
                   help='Comma-separated explicit archive scopes')
    p.add_argument('--sha256', required=True, help='Trusted expected archive SHA256, not a signature')
    p.add_argument('--remote-root', required=True)
    p.add_argument('--key', required=True)
    p.add_argument('--known-hosts', required=True)
    p.add_argument('--directory', default='/etc/fusionbox/cluster')
    p.add_argument('--timeout', type=int, default=300)
    p.add_argument('--confirm-owned-store', action='store_true')
    args = p.parse_args()
    archive.normalize_scopes(args.scope)
    if args.action != 'status' and not args.file:
        p.error('--file required for push/pull')
    run(args)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Archive transfer failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
