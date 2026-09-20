"""Configuration-only jobs: no production resources or services touched."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import backup_jobs as jobs


class Jobs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.conf, self.cron, self.state = jobs.paths(self.root, 'demo')
        self.conf.parent.mkdir(parents=True)
        self.conf.write_text(json.dumps({'owner': jobs.OWNER, 'scope': 'config', 'job': 'demo', 'hour': 3, 'minute': 0}))
        target = self.root / 'etc/nginx'
        target.mkdir()
        (target / 'nginx.conf').write_text('fixture')

    @unittest.skipIf(os.name == 'nt', 'POSIX cron paths and flock require Linux')
    def test_create_list_remove_owned_job(self):
        self.conf.unlink()
        jobs.create(self.root, 'demo', 3, 5, True)
        self.assertIn('5 3 * * * root ', self.cron.read_text())
        self.assertEqual(self.conf.stat().st_mode & 0o777, 0o600)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            jobs.listing(self.root)
        self.assertIn('demo 03:05', output.getvalue())
        jobs.remove(self.root, 'demo')
        self.assertFalse(self.cron.exists())
        self.assertFalse(self.conf.exists())

    def test_invalid_job_and_missing_ack_rejected(self):
        with self.assertRaises(ValueError):
            jobs.paths(self.root, '../bad;true')
        with self.assertRaises(ValueError):
            jobs.create(self.root, 'valid', 3, 0, False)

    def test_unknown_cron_preserved(self):
        self.cron.parent.mkdir(parents=True)
        self.cron.write_text('# user cron\nsecret command\n')
        with self.assertRaises(ValueError):
            jobs.remove(self.root, 'demo')
        self.assertEqual(self.cron.read_text(), '# user cron\nsecret command\n')
        self.assertTrue(self.conf.exists())

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_success_manifest_and_permissions(self):
        jobs.run(self.root, 'demo')
        archives = list(self.state.glob('*.tar.gz'))
        self.assertEqual(len(archives), 1)
        import tarfile
        with tarfile.open(archives[0]) as tf:
            self.assertEqual(jobs.archive.validate(tf, 'config'), ['etc/nginx'])
        self.assertEqual(archives[0].stat().st_mode & 0o777, 0o600)
        self.assertTrue(json.loads((self.state / 'status.json').read_text())['success'])

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_archive_failure_no_partial_publication(self):
        with patch.object(jobs.archive.tarfile.TarFile, 'addfile', side_effect=OSError('injected')):
            with self.assertRaises(OSError):
                jobs.run(self.root, 'demo')
        self.assertFalse(list(self.state.glob('*.tar.gz')))
        self.assertFalse(list(self.state.glob('.fusionbox-archive-*')))
        self.assertFalse(json.loads((self.state / 'status.json').read_text())['success'])

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_concurrent_run_refused(self):
        import fcntl
        self.state.mkdir(parents=True)
        with (self.state / 'run.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, 'already running'):
                jobs.run(self.root, 'demo')
        self.assertFalse(list(self.state.glob('*.tar.gz')))

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_retention_preview_apply_and_unknown_preserved(self):
        for _ in range(3):
            jobs.run(self.root, 'demo')
        names = sorted(jobs.inventory(self.state)['archives'])
        unknown = self.state / 'config-20000101T000000.000000Z.tar.gz'
        unknown.write_text('user archive')
        jobs.retention(self.root, 'demo', 1)
        self.assertTrue(all((self.state / n).exists() for n in names))
        jobs.retention(self.root, 'demo', 1, True)
        self.assertEqual(list(jobs.inventory(self.state)['archives']), names[-1:])
        self.assertTrue(unknown.exists())
        self.assertFalse((self.state / names[0]).exists())

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_retention_corruption_blocks_all_deletion(self):
        for _ in range(2):
            jobs.run(self.root, 'demo')
        names = sorted(jobs.inventory(self.state)['archives'])
        (self.state / names[-1]).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            jobs.retention(self.root, 'demo', 1, True)
        self.assertTrue((self.state / names[0]).exists())
        with self.assertRaises(ValueError):
            jobs.retention(self.root, 'demo', 0, True)

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_owned_restore_ack_and_roundtrip(self):
        jobs.run(self.root, 'demo')
        name = next(iter(jobs.inventory(self.state)['archives']))
        target = self.root / 'etc/nginx/nginx.conf'
        target.write_text('changed')
        with self.assertRaises(ValueError):
            jobs.recover(self.root, 'demo', name)
        self.assertEqual(target.read_text(), 'changed')
        jobs.recover(self.root, 'demo', name, True)
        self.assertEqual(target.read_text(), 'fixture')
        self.assertEqual(next((self.root / 'etc').glob('.fusionbox-restore-*/previous/nginx.conf')).read_text(), 'changed')
        with self.assertRaises(ValueError):
            jobs.recover(self.root, 'demo', '../unknown', True)

    @unittest.skipIf(os.name == 'nt', 'POSIX links')
    def test_linked_archive_and_lock_refused(self):
        jobs.run(self.root, 'demo')
        name = next(iter(jobs.inventory(self.state)['archives']))
        os.link(self.state / name, self.root / 'linked')
        with self.assertRaisesRegex(ValueError, 'linked'):
            jobs.retention(self.root, 'demo', 1, True)
        (self.state / 'run.lock').unlink()
        (self.state / 'run.lock').symlink_to(self.root / 'untouched')
        with self.assertRaises(OSError):
            jobs.run(self.root, 'demo')
        self.assertFalse((self.root / 'untouched').exists())

    def test_gzip_trailer_corruption_no_restore_mutation(self):
        target = self.root / 'etc/nginx/nginx.conf'
        source = self.root / 'snapshot.tar.gz'
        jobs.archive.create(source, 'config', self.root)
        damaged = bytearray(source.read_bytes())
        damaged[-8] ^= 1
        source.write_bytes(damaged)
        target.write_text('live')
        with self.assertRaises(OSError):
            jobs.archive.restore(source, 'config', self.root, conflict='replace')
        self.assertEqual(target.read_text(), 'live')
        self.assertFalse(list((self.root / 'etc').glob('.fusionbox-restore-*')))

    @unittest.skipIf(os.name == 'nt', 'flock requires Linux')
    def test_inventory_publication_failure_leaves_unowned_archive(self):
        original = jobs.atomic
        def fail(path, *args):
            if path.name == 'inventory.json':
                raise OSError('injected inventory failure')
            return original(path, *args)
        with patch.object(jobs, 'atomic', side_effect=fail):
            with self.assertRaises(OSError):
                jobs.run(self.root, 'demo')
        jobs.retention(self.root, 'demo', 1, True)
        self.assertEqual(len(list(self.state.glob('*.tar.gz'))), 1)

    def test_legacy_report_redacts_and_never_rewrites(self):
        self.cron.parent.mkdir(parents=True)
        text = '0 3 * * * root tar czf /tmp/site_backup_x.tar.gz /var/www; scp token-secret\n'
        self.cron.write_text(text)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            jobs.legacy(self.root)
        self.assertIn('manual review required', output.getvalue())
        self.assertNotIn('token-secret', output.getvalue())
        self.assertEqual(self.cron.read_text(), text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
