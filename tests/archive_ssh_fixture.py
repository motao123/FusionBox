"""Opt-in single-server loopback SSH fixture; not two-host disaster recovery.
Uses installed sshd with isolated host/client keys, config and authorized_keys.
Never edits production SSH configuration or restarts its service.
"""
import argparse
import hashlib
import os
from pathlib import Path
import pwd
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src/lib'))
import archive
import archive_transfer as transfer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true', required=True)
    parser.parse_args()
    sshd = shutil.which('sshd') or '/usr/sbin/sshd'
    if not Path(sshd).exists():
        raise RuntimeError('Installed sshd required; fixture never installs or changes services')
    checks = 0
    def check(value, label):
        nonlocal checks
        if not value:
            raise AssertionError(label)
        checks += 1
        print('PASS ' + label, flush=True)
    with tempfile.TemporaryDirectory(prefix='fusionbox-ssh-') as directory:
        root = Path(directory)
        os.chmod(root, 0o700)
        for name in ('host', 'client', 'wrong'):
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root / name)], check=True)
        authorized = root / 'authorized_keys'
        authorized.write_text('restrict ' + (root / 'client.pub').read_text())
        authorized.chmod(0o600)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        user = pwd.getpwuid(os.geteuid()).pw_name
        config = root / 'sshd_config'
        config.write_text(f'''ListenAddress 127.0.0.1
Port {port}
HostKey {root / 'host'}
PidFile {root / 'pid'}
AuthorizedKeysFile {authorized}
# Fixture directory is created private and owned; /tmp is sticky and shared.
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin prohibit-password
UsePAM no
AllowUsers {user}
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
PermitUserRC no
LogLevel VERBOSE
''')
        config.chmod(0o600)
        subprocess.run([sshd, '-t', '-f', str(config)], check=True)
        with (root / 'sshd.log').open('wb') as log:
            daemon = subprocess.Popen([sshd, '-D', '-e', '-f', str(config)], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=1):
                            break
                    except OSError:
                        if daemon.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError('Isolated sshd failed to start')
                        time.sleep(.1)
                hosts = root / 'known_hosts'
                hosts.write_text(f'[127.0.0.1]:{port} ' + (root / 'host.pub').read_text())
                hosts.chmod(0o600)
                registry = root / 'nodes'; registry.mkdir(mode=0o700)
                transfer.cluster_nodes.write(registry / 'nodes.conf', f'fixture|{user}@127.0.0.1|{port}\n')
                store = root / 'store'; store.mkdir(mode=0o700)
                local = root / 'local'; local.mkdir(mode=0o700)
                source_root = root / 'source'
                (source_root / 'etc/nginx').mkdir(parents=True)
                (source_root / 'etc/nginx/fixture.conf').write_text('fixture only\n')
                source = local / 'source.tar.gz'
                archive.create(source, 'config', source_root)
                sha = hashlib.sha256(source.read_bytes()).hexdigest()
                common = ['--directory', str(registry), '--scope', 'config', '--sha256', sha,
                          '--remote-root', str(store), '--key', str(root / 'client'),
                          '--known-hosts', str(hosts), '--confirm-owned-store', '--timeout', '10']
                def call(action, filename=None, extra=()):
                    cmd = [sys.executable, str(ROOT / 'src/lib/archive_transfer.py'), action, 'fixture', 'test.tar.gz', *common]
                    if filename is not None:
                        cmd += ['--file', str(filename)]
                    return subprocess.run(cmd + list(extra), capture_output=True, timeout=30)
                first = call('push', source)
                if first.returncode:
                    print(first.stderr.decode(), flush=True)
                    probe = transfer.ssh_command(dict(id='fixture', user=user, host='127.0.0.1', port=port), root / 'client', hosts, 'true')
                    print(subprocess.run(probe, capture_output=True).stderr.decode(), flush=True)
                    print((root / 'sshd.log').read_text(), flush=True)
                check(first.returncode == 0, 'real SSH push')
                remote = store / 'test.tar.gz'
                check(remote.read_bytes() == source.read_bytes(), 'remote exact bytes')
                check(remote.stat().st_mode & 0o777 == 0o600, 'remote private permissions')
                check(call('status').returncode == 0, 'remote verified status')
                check(call('push', source).returncode == 0, 'idempotent retry')
                downloaded = local / 'download.tar.gz'
                check(call('pull', downloaded).returncode == 0, 'real SSH pull')
                check(downloaded.read_bytes() == source.read_bytes(), 'download hash and manifest')
                check(not (local / 'etc').exists(), 'download never extracts')
                check(call('pull', downloaded).returncode == 0, 'idempotent pull')
                downloaded.write_bytes(b'keep local')
                check(call('pull', downloaded).returncode != 0 and downloaded.read_bytes() == b'keep local', 'local conflict preserved')
                remote.write_bytes(b'keep remote')
                check(call('push', source).returncode != 0 and remote.read_bytes() == b'keep remote', 'remote conflict preserved')
                missing = local / 'missing.tar.gz'
                check(call('pull', missing).returncode != 0 and not missing.exists(), 'corrupt remote rejected')
                remote.unlink()
                remote.symlink_to(source)
                check(call('push', source).returncode != 0, 'remote symlink refused')
                remote.unlink()
                # Send malformed bytes through real SSH to exercise remote cleanup.
                node = dict(id='fixture', user=user, host='127.0.0.1', port=port)
                import shlex
                def raw(data, size, expected):
                    code = transfer.REMOTE + '\ntransfer(*sys.argv[1:])'
                    command = shlex.join(['python3', '-c', code, 'push', str(store), 'test.tar.gz', expected, str(size), '10'])
                    return subprocess.run(transfer.ssh_command(node, root / 'client', hosts, command), input=data,
                                          capture_output=True, timeout=25)
                check(raw(b'bad', 3, sha).returncode != 0 and list(store.iterdir()) == [], 'SSH checksum failure cleans temporary')
                check(raw(b'partial', 100, sha).returncode != 0 and list(store.iterdir()) == [], 'SSH partial transfer cleans temporary')
                check(call('push', source, ['--key', str(root / 'wrong')]).returncode != 0, 'wrong authentication key rejected')
                hosts.write_text(f'[127.0.0.1]:{port} ' + (root / 'wrong.pub').read_text())
                check(call('push', source).returncode != 0 and list(store.iterdir()) == [], 'changed host key rejected')
                check(hashlib.sha256(source.read_bytes()).hexdigest() == sha, 'all failures retain original source')
                check(not list(local.glob('.transfer-*')), 'local temporary files cleaned')
            finally:
                daemon.terminate()
                try:
                    daemon.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    daemon.kill(); daemon.wait(timeout=5)
        check(daemon.poll() is not None, 'isolated sshd stopped')
    check(not root.exists(), 'fixture keys and files removed')
    print(f'SSH fixture: {checks} checks passed; single-server loopback only')


if __name__ == '__main__':
    main()
