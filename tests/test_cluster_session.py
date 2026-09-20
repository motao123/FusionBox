import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
if sys.platform != 'win32':
    import cluster_session as session


@unittest.skipIf(sys.platform == 'win32', 'POSIX descriptors and permissions required')
class ClusterSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.registry = self.root / 'cluster'
        self.registry.mkdir(mode=0o700)
        nodes = self.registry / 'nodes.conf'
        nodes.write_text('node1|deploy@127.0.0.1|30222\n')
        nodes.chmod(0o600)
        self.hosts = self.registry / 'known_hosts'
        self.hosts.touch(mode=0o600)
        self.node = {'id': 'node1', 'user': 'deploy', 'host': '127.0.0.1', 'port': 30222}

    def test_key_mode_is_default_and_cannot_fallback(self):
        with patch.object(session.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(session.run_ssh(self.node, self.hosts, ['true']), 0)
        argv = run.call_args.args[0]
        for option in ('BatchMode=yes', 'PasswordAuthentication=no', 'KbdInteractiveAuthentication=no',
                       'StrictHostKeyChecking=yes', 'GlobalKnownHostsFile=/dev/null'):
            self.assertIn(option, argv)
        self.assertNotIn('accept-new', argv)

    def test_password_uses_fd_and_never_argv(self):
        secret = 'secret value with spaces'
        observed = {}
        real_popen = subprocess.Popen

        def fake_ssh(argv, env, **kwargs):
            observed['argv'] = argv
            observed['env'] = env
            observed['mode'] = stat_mode(Path(env['SSH_ASKPASS']).parent)
            observed['script_mode'] = stat_mode(Path(env['SSH_ASKPASS']))
            observed['directory'] = Path(env['SSH_ASKPASS']).parent
            observed['process'] = real_popen([env['SSH_ASKPASS'], "deploy@localhost's password: "],
                                             env=env, stdout=subprocess.PIPE, **kwargs)
            return observed['process']

        with patch.object(session.subprocess, 'Popen', side_effect=fake_ssh) as launch:
            self.assertEqual(session.run_ssh(self.node, self.hosts, ['true'], password=secret), 0)
        with observed['process'].stdout as output:
            self.assertEqual(output.read(), (secret + '\n').encode())
        self.assertNotIn(secret, '\0'.join(observed['argv']))
        self.assertNotIn(secret, '\0'.join(f'{k}={v}' for k, v in observed['env'].items()))
        self.assertTrue(launch.call_args.kwargs['start_new_session'])
        self.assertEqual(observed['mode'], 0o700)
        self.assertEqual(observed['script_mode'], 0o700)
        self.assertFalse(observed['directory'].exists())

    def test_password_fd_input(self):
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b'one shot\nignored')
        os.close(write_fd)
        try:
            self.assertEqual(session.read_password(read_fd), 'one shot')
        finally:
            os.close(read_fd)

    def test_changed_host_key_is_rejected_without_write(self):
        original = 'host ssh-ed25519 AAAAold\n'
        self.hosts.write_text(original)
        scan = subprocess.CompletedProcess([], 0, 'host ssh-ed25519 AAAAnew\n', '')
        find = subprocess.CompletedProcess([], 0, original, '')
        with patch.object(session.subprocess, 'run', side_effect=[find, scan, find]), \
             self.assertRaisesRegex(RuntimeError, 'changed'):
            session.trust(self.node, self.hosts)
        self.assertEqual(self.hosts.read_text(), original)

    def test_askpass_second_prompt_fails_without_blocking(self):
        runner = self.root / 'fake-ssh'
        runner.write_text(r'''#!/usr/bin/env python3
import os, subprocess, sys
askpass = os.environ['SSH_ASKPASS']
first = subprocess.run([askpass, "fixture@localhost's password: "], capture_output=True, timeout=3)
second = subprocess.run([askpass, "fixture@localhost's password: "], capture_output=True, timeout=3)
changed = subprocess.run([askpass, "New password: "], capture_output=True, timeout=3)
sys.exit(0 if first.returncode == 0 and first.stdout == b'one-shot\n' and second.returncode != 0 and not second.stdout and changed.returncode != 0 else 1)
''')
        runner.chmod(0o700)
        self.assertEqual(session.password_run([str(runner)], 'one-shot'), 0)

    def test_password_change_prompt_never_receives_credential(self):
        runner = self.root / 'fake-change'
        runner.write_text(r'''#!/usr/bin/env python3
import os, subprocess, sys
result = subprocess.run([os.environ['SSH_ASKPASS'], 'New password: '], capture_output=True, timeout=3)
sys.exit(0 if result.returncode != 0 and not result.stdout else 1)
''')
        runner.chmod(0o700)
        self.assertEqual(session.password_run([str(runner)], 'private'), 0)

    def test_known_hosts_without_final_newline_preserves_old_pin(self):
        old = 'old.example ssh-ed25519 AAAAold'
        new = 'new.example ssh-ed25519 AAAAnew'
        self.hosts.write_text(old)
        with patch.object(session, '_host_entries_fd', return_value=[]):
            session._append_host_keys(self.hosts, 'new.example', [new])
        self.assertEqual(self.hosts.read_text(), old + '\n' + new + '\n')

    def test_known_hosts_error_never_appends(self):
        self.hosts.write_text('old\n')
        with patch.object(session.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'I/O error')), \
             self.assertRaisesRegex(RuntimeError, 'Unable to check'):
            session._append_host_keys(self.hosts, 'host', ['new'])
        self.assertEqual(self.hosts.read_text(), 'old\n')

    def test_group_cleanup_when_leader_exited(self):
        import signal
        import time
        pid_file = self.root / 'child.pid'
        script = '''import os, signal, sys, time
pid = os.fork()
if pid == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    open(sys.argv[1], 'w').write(str(os.getpid()))
    while True: time.sleep(1)
else:
    while not os.path.exists(sys.argv[1]): time.sleep(.01)
'''
        process = subprocess.Popen([sys.executable, '-c', script, str(pid_file)], start_new_session=True)
        try:
            process.wait(timeout=4)
            pid = int(pid_file.read_text())
            session.terminate_process_group(process, grace=.1)
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                status = Path(f'/proc/{pid}/stat')
                if not status.exists() or status.read_text().split()[2] == 'Z':
                    break
                time.sleep(.02)
            else:
                self.fail('child process survived group cleanup')
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)

    def test_inventory_has_no_credentials(self):
        node = session.select(self.registry, 'node1')
        self.assertEqual(set(node), {'id', 'user', 'host', 'port'})


def stat_mode(path):
    return path.stat().st_mode & 0o777


if __name__ == '__main__':
    unittest.main()
