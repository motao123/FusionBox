"""Linux storage and SSH boundary regressions; no external connections."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
if sys.platform != 'win32':
    import archive
    import archive_transfer as transfer


@unittest.skipIf(sys.platform == 'win32', 'Linux descriptor and permission semantics')
class TransferTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.store = self.root / 'store'
        self.store.mkdir(mode=0o700)
        self.data = b'archive bytes'
        self.sha = hashlib.sha256(self.data).hexdigest()

    def remote(self, action='push', data=None, sha=None, name='test.tar.gz', root=None, size=None):
        data = self.data if data is None else data
        return subprocess.run([sys.executable, '-c', transfer.REMOTE + '\ntransfer(*sys.argv[1:])',
                               action, str(root or self.store), name, sha or self.sha,
                               str(len(data) if size is None else size), '5'], input=data,
                              capture_output=True, timeout=10)

    def test_roundtrip_status_private_cleanup(self):
        self.assertEqual(self.remote().returncode, 0)
        self.assertEqual((self.store / 'test.tar.gz').stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.remote('pull').stdout, self.data)
        self.assertEqual(self.remote('status').returncode, 0)
        self.assertEqual(len(list(self.store.iterdir())), 1)

    def test_idempotent_retry(self):
        self.assertEqual(self.remote().returncode, 0)
        self.assertEqual(self.remote().returncode, 0)

    def test_conflict_preserved(self):
        self.assertEqual(self.remote().returncode, 0)
        self.assertNotEqual(self.remote(data=b'new', sha=hashlib.sha256(b'new').hexdigest()).returncode, 0)
        self.assertEqual((self.store / 'test.tar.gz').read_bytes(), self.data)

    def test_mismatch_cleanup(self):
        self.assertNotEqual(self.remote(sha='0' * 64).returncode, 0)
        self.assertEqual(list(self.store.iterdir()), [])

    def test_partial_cleanup_retry_failure(self):
        for _ in range(2):
            self.assertNotEqual(self.remote(size=1000).returncode, 0)
            self.assertEqual(list(self.store.iterdir()), [])

    def test_excess_cleanup(self):
        self.assertNotEqual(self.remote(size=1).returncode, 0)
        self.assertEqual(list(self.store.iterdir()), [])

    def test_symlink_file(self):
        victim = self.root / 'victim'
        victim.write_bytes(b'keep')
        (self.store / 'test.tar.gz').symlink_to(victim)
        self.assertNotEqual(self.remote().returncode, 0)
        self.assertNotEqual(self.remote('pull').returncode, 0)
        self.assertEqual(victim.read_bytes(), b'keep')

    def test_symlink_store_and_ancestor(self):
        link = self.root / 'link'
        link.symlink_to(self.store, target_is_directory=True)
        self.assertNotEqual(self.remote(root=link).returncode, 0)
        nested = self.store / 'nested'
        nested.mkdir(mode=0o700)
        self.assertNotEqual(self.remote(root=link / 'nested').returncode, 0)

    def test_world_readable_store(self):
        self.store.chmod(0o755)
        self.assertNotEqual(self.remote().returncode, 0)

    def test_bad_paths_names_hashes(self):
        for name in ('../bad.tar.gz', '-o.tar.gz', 'a;touch bad.tar.gz', 'a\nb.tar.gz'):
            with self.subTest(name=name):
                self.assertNotEqual(self.remote(name=name).returncode, 0)
        for root in ('/', str(self.store) + '/../store', str(self.store) + ';id', str(self.store) + '//'):
            self.assertNotEqual(self.remote(root=root).returncode, 0)
        self.assertNotEqual(self.remote(sha='$(id)').returncode, 0)

    def test_fifo_and_hardlinks_rejected(self):
        target = self.store / 'test.tar.gz'
        os.mkfifo(target, 0o600)
        self.assertNotEqual(self.remote('pull').returncode, 0)
        target.unlink()
        self.assertEqual(self.remote().returncode, 0)
        os.link(target, self.store / 'other')
        self.assertNotEqual(self.remote('status').returncode, 0)

    def test_ssh_strict_no_password_or_config(self):
        key = self.root / 'key'; key.touch(mode=0o600)
        hosts = self.root / 'hosts'; hosts.touch(mode=0o600)
        node = dict(id='n', host='::1', user='root', port=2222)
        cmd = transfer.ssh_command(node, key, hosts, 'true')
        for option in ('StrictHostKeyChecking=yes', 'BatchMode=yes', 'PasswordAuthentication=no',
                       'KbdInteractiveAuthentication=no', 'IdentityAgent=none', 'GlobalKnownHostsFile=/dev/null'):
            self.assertIn(option, cmd)
        self.assertEqual(cmd[1:3], ['-F', '/dev/null'])
        for host in ('-oProxyCommand=id', 'host;id', '$(id)', 'a\nb'):
            with self.assertRaises(ValueError):
                transfer.ssh_command(dict(node, host=host), key, hosts, 'true')

    def test_pull_failed_process_does_not_publish(self):
        self.client_failure('pull', valid=True)

    def test_pull_bad_manifest_does_not_publish(self):
        self.client_failure('pull', valid=False)

    def test_push_failure_preserves_source(self):
        self.client_failure('push', valid=True)

    def test_docker_kind_uses_bundle_verifier(self):
        from argparse import Namespace
        registry = self.root / 'registry'
        registry.mkdir(mode=0o700)
        transfer.cluster_nodes.write(registry / 'nodes.conf', 'n|root@localhost|22\n')
        source = self.root / 'docker.tar.gz'
        source.write_bytes(b'docker bundle')
        source.chmod(0o600)
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        key = self.root / 'key'; key.touch(mode=0o600)
        hosts = self.root / 'hosts'; hosts.touch(mode=0o600)
        args = Namespace(action='push', confirm_owned_store=True, remote_root=str(self.store),
                         name='docker.tar.gz', sha256=expected, timeout=5, directory=str(registry),
                         node='n', file=str(source), scope=None, kind='docker-v1', key=str(key), known_hosts=str(hosts))
        with patch.object(transfer.docker_migration, 'verify') as verify, \
             patch.object(transfer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaises(RuntimeError):
                transfer.run(args)
        verify.assert_called_once()

    def client_failure(self, action, valid):
        from argparse import Namespace
        registry = self.root / 'registry'
        registry.mkdir(mode=0o700)
        transfer.cluster_nodes.write(registry / 'nodes.conf', 'n|root@localhost|22\n')
        source = self.root / 'source.tar.gz'
        if valid:
            (self.root / 'etc/nginx').mkdir(parents=True)
            archive.create(source, 'config', self.root)
        else:
            source.write_bytes(self.data)
            source.chmod(0o600)
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        target = source if action == 'push' else self.root / 'download.tar.gz'
        key = self.root / 'key'; key.touch(mode=0o600)
        hosts = self.root / 'hosts'; hosts.touch(mode=0o600)
        args = Namespace(action=action, confirm_owned_store=True, remote_root=str(self.store),
                         name='test.tar.gz', sha256=expected, timeout=5, directory=str(registry),
                         node='n', file=str(target), scope='config', kind='system-v2', key=str(key), known_hosts=str(hosts))
        def failure(argv, **kwargs):
            if action == 'pull':
                kwargs['stdout'].write(source.read_bytes())
            return subprocess.CompletedProcess(argv, 1)
        with patch.object(transfer.subprocess, 'run', side_effect=failure):
            with self.assertRaises(Exception):
                transfer.run(args)
        self.assertTrue(source.exists())
        if action == 'pull':
            self.assertFalse(target.exists())
        self.assertFalse(list(self.root.glob('.transfer-*')))


if __name__ == '__main__':
    unittest.main()
