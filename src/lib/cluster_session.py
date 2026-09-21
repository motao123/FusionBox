"""Strict, ephemeral SSH sessions for one cluster node."""
import argparse
import errno
import fcntl
import getpass
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager

import cluster_nodes


def private_file(path, create=False):
    path = cluster_nodes.safe(path, missing=create)
    if create and not path.exists():
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        os.close(fd)
    return cluster_nodes.safe(path)


def select(directory, name):
    with cluster_nodes.locked(directory) as inventory:
        matches = [item for item in cluster_nodes.legacy(inventory) if item['id'] == name]
    if not matches:
        raise ValueError('Unknown node ID')
    return matches[0]


def host_token(node):
    host = node['host']
    return f'[{host}]:{node["port"]}' if node['port'] != 22 else host


def target(node):
    return f'{node["user"]}@{node["host"]}'


def base_options(node, known_hosts):
    return ['-F', '/dev/null', '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={known_hosts}',
            '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'CheckHostIP=no', '-o', 'ConnectTimeout=10',
            '-o', 'ConnectionAttempts=1', '-o', 'IdentityAgent=none', '-p', str(node['port'])]


def key_options(node, known_hosts):
    return base_options(node, known_hosts) + ['-o', 'BatchMode=yes', '-o', 'PasswordAuthentication=no',
                                               '-o', 'KbdInteractiveAuthentication=no']


def read_password(fd):
    if fd is None:
        value = getpass.getpass('SSH password (this session only): ')
    else:
        data = bytearray()
        while len(data) <= 4096:
            part = os.read(fd, 4097 - len(data))
            if not part:
                break
            data.extend(part)
            if b'\n' in part:
                break
        if len(data) > 4096 or b'\x00' in data:
            raise ValueError('Invalid password input')
        value = bytes(data).split(b'\n', 1)[0].rstrip(b'\r').decode('utf-8')
    if not value:
        raise ValueError('Empty passwords are not supported')
    return value


def terminate_process_group(process, grace=1):
    """Bounded cleanup of a session we created, including children of a dead leader."""
    if process is None:
        return
    # poll()/wait() only describe the leader. Always signal the owned PGID,
    # and test the group itself throughout the TERM grace period.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    else:
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            process.poll()  # reap the leader if possible, without ending group cleanup
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            time.sleep(min(0.02, max(0, deadline - time.monotonic())))
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    # Even an uninterruptible child must not make local cleanup wait forever.
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        raise RuntimeError('SSH process did not exit after group cleanup') from None


def password_run(argv, password, **kwargs):
    payload = password.encode('utf-8')
    if not payload or len(payload) > 4096 or any(value in payload for value in (b'\n', b'\r', b'\x00')):
        raise ValueError('Password must be one nonempty line of at most 4096 bytes')
    directory = tempfile.mkdtemp(prefix='fusionbox-askpass-')
    script = Path(directory) / 'askpass'
    fifo = Path(directory) / 'password.pipe'
    marker = Path(directory) / 'password.used'
    cancel = threading.Event()
    errors = []
    writer = None
    process = None
    old_handlers = {}
    starting = False
    interrupt_requested = False
    cleaning = False

    def provide_password():
        fd = None
        try:
            while not cancel.is_set():
                try:
                    fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                    break
                except OSError as error:
                    if error.errno != errno.ENXIO:
                        raise
                    cancel.wait(0.02)
            if fd is not None:
                remaining = memoryview(payload + b'\n')
                while remaining and not cancel.is_set():
                    try:
                        written = os.write(fd, remaining)
                        if not written:
                            raise OSError('Incomplete password handoff')
                        remaining = remaining[written:]
                    except BlockingIOError:
                        cancel.wait(0.02)
        except OSError:
            if not cancel.is_set():
                errors.append('Password handoff failed')
        finally:
            if fd is not None:
                os.close(fd)

    signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)

    def ignore_signals():
        for signum in old_handlers:
            signal.signal(signum, signal.SIG_IGN)

    def interrupted(signum, frame):
        nonlocal interrupt_requested
        # Repeats cannot interrupt handler installation or cleanup. Defer the
        # first exception during Popen until its owned PGID has been recorded.
        if cleaning or interrupt_requested:
            return
        interrupt_requested = True
        if not starting:
            raise KeyboardInterrupt

    try:
        os.chmod(directory, 0o700)
        os.mkfifo(fifo, 0o600)
        script.write_text(
            '#!/bin/sh\n'
            'set -eu\n'
            'umask 077\n'
            # Only OpenSSH's initial password prompt is supported. Never send
            # the credential to a password-change/confirmation/unknown prompt.
            "case \"${1-}\" in *\"'s password: \") ;; *) exit 1 ;; esac\n"
            '(set -C; : > "$FUSION_PASSWORD_MARKER") 2>/dev/null || exit 1\n'
            'IFS= read -r answer < "$FUSION_PASSWORD_FIFO" || exit 1\n'
            'printf "%s\\n" "$answer"\n',
            encoding='ascii',
        )
        script.chmod(0o700)
        env = os.environ.copy()
        env.pop('FUSION_PASSWORD_FD', None)
        env.update(SSH_ASKPASS=str(script), SSH_ASKPASS_REQUIRE='force', DISPLAY='fusionbox:0',
                   LC_ALL='C', FUSION_PASSWORD_FIFO=str(fifo), FUSION_PASSWORD_MARKER=str(marker))
        for signum in signals:
            old_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, interrupted)
        writer = threading.Thread(target=provide_password, name='fusionbox-password-writer', daemon=True)
        writer.start()
        options = ['-o', 'BatchMode=no', '-o', 'PubkeyAuthentication=no', '-o', 'PreferredAuthentications=password',
                   '-o', 'KbdInteractiveAuthentication=no', '-o', 'NumberOfPasswordPrompts=1']
        starting = True
        try:
            process = subprocess.Popen(argv[:1] + options + argv[1:], env=env, start_new_session=True, **kwargs)
        finally:
            starting = False
        if interrupt_requested:
            raise KeyboardInterrupt
        returncode = process.wait()
    finally:
        cleaning = True
        ignore_signals()
        cancel.set()
        try:
            try:
                terminate_process_group(process)
            finally:
                if writer is not None:
                    writer.join(timeout=2)
                password = None
                payload = b''
                shutil.rmtree(directory)
        finally:
            for signum, handler in old_handlers.items():
                signal.signal(signum, handler)
    if writer.is_alive():
        raise RuntimeError('Password writer did not stop')
    if returncode == 0 and errors:
        raise RuntimeError(errors[0])
    return returncode


def run_ssh(node, known_hosts, command, password=None, stdin=None, tty=False, identity=None):
    options = base_options(node, known_hosts) if password is not None else key_options(node, known_hosts)
    if identity:
        options += ['-o', f'IdentityFile={identity}', '-o', 'IdentitiesOnly=yes']
    argv = ['ssh'] + (['-tt'] if tty else []) + options + [target(node)] + command
    if password is not None:
        return password_run(argv, password, stdin=stdin)
    return subprocess.run(argv, stdin=stdin).returncode


def _check_host_path(known_hosts, fd):
    cluster_nodes.safe(known_hosts)
    current = os.stat(known_hosts, follow_symlinks=False)
    locked = os.fstat(fd)
    if (current.st_dev, current.st_ino) != (locked.st_dev, locked.st_ino):
        raise RuntimeError('Host key file path changed while locked')


@contextmanager
def _locked_host_file(known_hosts, write=False):
    known_hosts = cluster_nodes.safe(known_hosts)
    fd = os.open(known_hosts, (os.O_RDWR | os.O_APPEND if write else os.O_RDONLY) | os.O_NOFOLLOW)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        _check_host_path(known_hosts, fd)
        yield fd
        _check_host_path(known_hosts, fd)
    finally:
        os.close(fd)  # also releases flock on every error path


def _host_entries_fd(known_hosts, token, fd):
    _check_host_path(known_hosts, fd)
    # The child reads the locked inode, not a path which could have been
    # replaced while waiting for flock. /dev/fd is provided on our POSIX hosts.
    os.lseek(fd, 0, os.SEEK_SET)
    result = subprocess.run(['ssh-keygen', '-F', token, '-f', f'/dev/fd/{fd}'],
                            pass_fds=(fd,), capture_output=True, text=True)
    _check_host_path(known_hosts, fd)
    # OpenSSH uses 1 with empty output for "not found", also 1 for some I/O
    # errors (with stderr). Anything ambiguous fails closed.
    if result.returncode == 1 and not result.stdout and not result.stderr:
        return []
    if result.returncode != 0 or result.stderr:
        raise RuntimeError('Unable to check pinned host keys')
    entries = [line for line in result.stdout.splitlines() if line and not line.startswith('#')]
    if not entries:
        raise RuntimeError('Unable to check pinned host keys')
    return entries


def _host_entries(known_hosts, token):
    with _locked_host_file(known_hosts) as fd:
        return _host_entries_fd(known_hosts, token, fd)


def _append_host_keys(known_hosts, token, lines):
    with _locked_host_file(known_hosts, write=True) as fd:
        current_lines = _host_entries_fd(known_hosts, token, fd)
        if current_lines:
            if set(current_lines) != set(lines):
                raise RuntimeError('Host key changed; refusing replacement')
            print('Host key is already pinned and unchanged')
            return
        _check_host_path(known_hosts, fd)
        size = os.fstat(fd).st_size
        prefix = b'\n' if size and os.pread(fd, 1, size - 1) != b'\n' else b''
        remaining = memoryview(prefix + ('\n'.join(lines) + '\n').encode())
        while remaining:
            written = os.write(fd, remaining)
            if not written:
                raise OSError('Incomplete host key append')
            remaining = remaining[written:]
        os.fsync(fd)


def trust(node, known_hosts):
    token = host_token(node)
    found = bool(_host_entries(known_hosts, token))
    scan = subprocess.run(['ssh-keyscan', '-T', '5', '-p', str(node['port']), node['host']],
                          capture_output=True, text=True)
    lines = [line for line in scan.stdout.splitlines() if line and not line.startswith('#')]
    if scan.returncode or not lines:
        raise RuntimeError('Unable to scan host keys')
    fd, scan_file = tempfile.mkstemp(prefix='fusionbox-hostkey-', text=True)
    os.chmod(scan_file, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write('\n'.join(lines) + '\n')
    try:
        if found:
            current_lines = _host_entries(known_hosts, token)
            if set(current_lines) != set(lines):
                raise RuntimeError('Host key changed; refusing replacement')
            print('Host key is already pinned and unchanged')
            return
        fingerprints = subprocess.run(['ssh-keygen', '-lf', scan_file], check=True, capture_output=True,
                                      text=True).stdout
        print(fingerprints, end='')
        if input(f'Pin these host keys for {token}? Type YES: ') != 'YES':
            raise RuntimeError('Host key was not pinned')
        _append_host_keys(known_hosts, token, lines)
    finally:
        os.unlink(scan_file)


def public_key(path):
    if path is None:
        candidates = [Path.home() / '.ssh/id_ed25519.pub', Path.home() / '.ssh/id_rsa.pub']
        path = next((item for item in candidates if item.is_file()), None)
        if path is None:
            raise ValueError('No default public key found')
    path = Path(os.path.abspath(path))
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1:
        raise ValueError('Public key must be an operator-owned, singly linked regular file')
    data = path.read_bytes()
    if len(data) > 16384 or not re.fullmatch(rb'(ssh-(rsa|ed25519)|ecdsa-[^ ]+) [A-Za-z0-9+/=]+(?: [^\r\n]*)?\n?', data):
        raise ValueError('Invalid public key file')
    return path, data.rstrip(b'\r\n') + b'\n'


def migration_identity(key_path, data):
    if key_path.suffix != '.pub':
        raise ValueError('Migration public key must end in .pub with its matching private key beside it')
    identity = private_file(key_path.with_suffix(''))
    derived = subprocess.run(['ssh-keygen', '-y', '-P', '', '-f', str(identity)],
                             capture_output=True, timeout=10)
    if derived.returncode or derived.stdout.split()[:2] != data.split()[:2]:
        raise ValueError('Matching noninteractive private key required before remote changes')
    return str(identity)


def main():
    arguments = sys.argv[1:]
    remote_command = []
    if '--' in arguments:
        boundary = arguments.index('--')
        remote_command = arguments[boundary + 1:]
        arguments = arguments[:boundary]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', default='/etc/fusionbox/cluster')
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ('trust', 'connect', 'exec', 'migrate-key'):
        item = sub.add_parser(action)
        item.add_argument('node')
        if action != 'trust':
            mode = item.add_mutually_exclusive_group()
            mode.add_argument('--password', action='store_true')
            mode.add_argument('--password-fd', type=int)
        if action in ('connect', 'exec'):
            # run_ssh always supported an explicit identity; the CLI never exposed
            # it, leaving operators with default keys or an agent only. The
            # two-host fixture (and any dedicated migration key) needs this.
            item.add_argument('--identity', help='Private key for key-only authentication')
        if action == 'migrate-key':
            item.add_argument('--public-key')
    args = parser.parse_args(arguments)
    if args.action == 'exec' and not remote_command:
        parser.error('exec requires a command after --')
    if args.action != 'exec' and remote_command:
        parser.error('remote command is only valid for exec')
    node = select(args.directory, args.node)
    known_hosts = private_file(Path(args.directory) / 'known_hosts', create=True)
    if args.action == 'trust':
        trust(node, known_hosts)
        return
    password = read_password(args.password_fd) if args.password or args.password_fd is not None else None
    identity = getattr(args, 'identity', None)
    if args.action == 'connect':
        raise SystemExit(run_ssh(node, known_hosts, [], password=password, tty=True, identity=identity))
    if args.action == 'exec':
        command = remote_command[0] if len(remote_command) == 1 else shlex.join(remote_command)
        raise SystemExit(run_ssh(node, known_hosts, [command], password=password, identity=identity))
    key_path, data = public_key(args.public_key)
    identity = migration_identity(key_path, data)
    remote = ['set -eu; umask 077; '
              'test ! -L "$HOME/.ssh"; test ! -L "$HOME/.ssh/authorized_keys"; '
              'if test -e "$HOME/.ssh/authorized_keys"; then '
              'test -f "$HOME/.ssh/authorized_keys"; '
              'test "$(stat -c %h "$HOME/.ssh/authorized_keys")" = 1; fi; '
              'mkdir -p "$HOME/.ssh"; '
              'test "$(stat -c %u "$HOME/.ssh")" = "$(id -u)"; '
              'chmod 700 "$HOME/.ssh"; '
              'touch "$HOME/.ssh/authorized_keys"; '
              'test "$(stat -c %u "$HOME/.ssh/authorized_keys")" = "$(id -u)"; '
              'chmod 600 "$HOME/.ssh/authorized_keys"; '
              'IFS= read -r key; '
              'exec 9>>"$HOME/.ssh/authorized_keys"; flock -x 9; '
              'if test -s "$HOME/.ssh/authorized_keys"; then '
              'last=$(tail -c 1 "$HOME/.ssh/authorized_keys"); '
              'test -z "$last" || printf "\\n" >&9; fi; '
              'grep -Fqx -- "$key" "$HOME/.ssh/authorized_keys" || printf "%s\\n" "$key" >&9']
    with tempfile.TemporaryFile() as stream:
        stream.write(data)
        stream.seek(0)
        if run_ssh(node, known_hosts, remote, password=password, stdin=stream):
            raise RuntimeError('Public key installation failed')
    if run_ssh(node, known_hosts, ['true'], identity=identity):
        raise RuntimeError('Public key installed but key-only verification failed')
    print('Public key installed and verified with key-only authentication')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, RuntimeError, KeyboardInterrupt) as error:
        print('Cluster session failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
