"""Reliability checks: isolated files and mocked system commands only."""
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import unittest
from unittest.mock import patch
from test_safety import Safety, ROOT

spec = importlib.util.spec_from_file_location('archive', ROOT / 'src/lib/archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class Reliability(Safety):
    def test_dns_invalid_addresses_preserve_file(self):
        target = self.root / 'etc/resolv.conf'
        target.write_text('original')
        for value in ('999.1.1.1', 'abc', '1::2::3', '1.2.3'):
            self.run_shell('system', f'systemctl() {{ return 1; }}; _system_dns_apply test {value}', 1)
            self.assertEqual(target.read_text(), 'original')

    def test_dns_failed_activation_preserves_file(self):
        target = self.root / 'etc/resolv.conf'
        target.write_text('original')
        self.run_shell('system', 'systemctl() { return 1; }; mv() { return 23; }; _system_dns_apply test 1.1.1.1', 1)
        self.assertEqual(target.read_text(), 'original')

    def test_dns_valid_addresses(self):
        self.run_shell('system', 'systemctl() { return 1; }; _system_dns_apply test 1.1.1.1 2001:4860:4860::8888')
        self.assertEqual((self.root / 'etc/resolv.conf').read_text(), 'nameserver 1.1.1.1\nnameserver 2001:4860:4860::8888\n')

    def test_expired_partial_day_negative(self):
        out = self.run_shell('web', '''touch "$T/cert"
openssl() { printf 'notAfter=date\n'; }
date() { if [[ "$1" == -d ]]; then printf 999; else printf 1000; fi; }
_web_cert_days "$T/cert"''')
        self.assertEqual(out, '-1')

    def test_reload_failure_propagates(self):
        self.run_shell('web', 'certbot() { return 0; }; systemctl() { return 1; }; nginx() { return 1; }; web_ssl_renew', 1)

    def test_scheduler_activation_failure(self):
        self.run_shell('web', 'certbot() { :; }; _web_ssl_existing_schedule() { return 1; }; mv() { return 1; }; web_ssl_autorenew <<< 1', 1)
        self.assertFalse((self.root / 'etc/cron.d/fusionbox-cert-renew').exists())

    def test_cluster_bbr_failure(self):
        self.run_shell('cluster', '''sysctl() { return 19; }
entry="${CLUSTER_TASKS[3]}"; cmd="${entry#*|}"; cmd="${cmd#*|}"; eval "$cmd"''', 19)

    def test_cluster_swap_failure_does_not_write_fstab(self):
        text = Path(self.root / 'cluster.sh').read_text().replace('/swapfile', self.posix + '/swapfile')
        (self.root / 'cluster.sh').write_text(text)
        self.run_shell('cluster', '''swapon() { return 0; }; fallocate() { return 29; }
entry="${CLUSTER_TASKS[7]}"; cmd="${entry#*|}"; cmd="${cmd#*|}"; eval "$cmd"''', 29)
        self.assertFalse((self.root / 'etc/fstab').exists())

    def test_archive_roundtrip_and_recovery(self):
        target = self.root / 'var/www'
        target.mkdir(parents=True)
        (target / 'index').write_text('saved')
        backup = self.root / 'backup.tar.gz'
        archive.create(backup, 'web', self.root)
        (target / 'index').write_text('current')
        archive.restore(backup, 'web', self.root)
        self.assertEqual((target / 'index').read_text(), 'saved')
        self.assertEqual(next(target.parent.glob('.fusionbox-restore-*/previous/index')).read_text(), 'current')

    def test_archive_rejects_old_and_traversal(self):
        for name in ('var/www/index', '../escape'):
            backup = self.root / 'unsafe.tar.gz'
            with tarfile.open(backup, 'w:gz') as out:
                member = tarfile.TarInfo(name); member.size = 1
                out.addfile(member, io.BytesIO(b'x'))
            with self.assertRaises((ValueError, KeyError)):
                archive.restore(backup, 'web', self.root)
        self.assertFalse((self.root / 'var').exists())

    def test_archive_creation_failure_not_published(self):
        (self.root / 'var/www').mkdir(parents=True)
        destination = self.root / 'backup.tar.gz'
        with patch.object(tarfile.TarFile, 'add', side_effect=OSError('injected')):
            with self.assertRaises(OSError):
                archive.create(destination, 'web', self.root)
        self.assertFalse(destination.exists())
        self.assertFalse(list(self.root.glob('.fusionbox-archive-*')))

    def test_archive_activation_failure_rolls_back(self):
        target = self.root / 'var/www'
        target.mkdir(parents=True)
        (target / 'index').write_text('saved')
        backup = self.root / 'backup.tar.gz'
        archive.create(backup, 'web', self.root)
        (target / 'index').write_text('current')
        rename = Path.rename
        def fail_new(path, destination):
            if path.name == 'new':
                raise OSError('injected')
            return rename(path, destination)
        with patch.object(Path, 'rename', fail_new):
            with self.assertRaises(OSError):
                archive.restore(backup, 'web', self.root)
        self.assertEqual((target / 'index').read_text(), 'current')


if __name__ == '__main__':
    # Do not repeat inherited safety cases in this focused suite.
    names = [n for n in Reliability.__dict__ if n.startswith('test_')]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(Reliability(n) for n in names))
    raise SystemExit(not result.wasSuccessful())
