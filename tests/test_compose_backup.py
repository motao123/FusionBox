"""Isolated registered Compose lifecycle regressions."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import compose_backup as cb


class ComposeBackup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.compose = self.root / 'compose.yaml'
        self.compose.write_text('services: {}')
        self.record = {'owner': cb.OWNER, 'project': 'fixture', 'compose': str(self.compose.resolve())}
        self.data = {'services': {'one': {}}, 'volumes': {'data': {'name': 'fixture_data'}}}
        self.volume = self.root / 'volume'
        self.volume.mkdir()
        (self.volume / 'value').write_text('before')
        self.paths = {'fixture_data': self.volume}
        self.containers = [{'Id': 'running', 'State': {'Running': True}}, {'Id': 'stopped', 'State': {'Running': False}}]
        self.backup = self.root / 'backup.tar.gz'
        self.base = self.root / 'registry'
        self.base.mkdir()
        (self.base / 'fixture.json').write_text(json.dumps(self.record))
        self.addCleanup(patch.stopall)
        patch.object(cb, 'BASE', self.base).start()
        patch.object(cb, 'js', return_value=[]).start()

    def test_package_integrity_and_private_permissions(self):
        cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        self.assertTrue(cb.verify(self.backup, self.record, self.data, self.paths))
        if os.name != 'nt':
            self.assertEqual(self.backup.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(ValueError):
            cb.package(self.backup, self.record, self.data, self.containers, self.paths)

    def test_trailer_corruption_and_changed_config_rejected(self):
        cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        self.compose.write_text('changed')
        with self.assertRaises(ValueError):
            cb.verify(self.backup, self.record, self.data, self.paths)
        data = bytearray(self.backup.read_bytes()); data[-8] ^= 1
        self.backup.write_bytes(data)
        with self.assertRaises(OSError):
            cb.verify(self.backup, self.record, self.data, self.paths)

    def test_partial_stop_restarts_original_only(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[0] == 'stop':
                raise RuntimeError('injected')
        with patch.object(cb, 'docker', side_effect=command):
            with self.assertRaises(RuntimeError):
                with cb.stopped(self.containers):
                    self.fail('must not reach mutation')
        self.assertEqual(calls, [('stop', 'running'), ('start', 'running')])

    def test_snapshot_failure_and_restart_failure_propagate(self):
        with patch.object(cb, 'docker') as command:
            with self.assertRaisesRegex(RuntimeError, 'snapshot'):
                with cb.stopped(self.containers):
                    raise RuntimeError('snapshot')
            self.assertEqual(command.call_args_list[-1].args, ('start', 'running'))
        with patch.object(cb, 'docker', side_effect=[b'', RuntimeError('start')]):
            with self.assertRaisesRegex(RuntimeError, 'restart failed'):
                with cb.stopped(self.containers):
                    pass

    def test_acknowledgements_required(self):
        with self.assertRaises(ValueError): cb.register('fixture', self.compose, False)
        with self.assertRaises(ValueError): cb.operate('fixture', 'backup', self.backup, False)

    def test_bind_external_privileged_rejected(self):
        for data in ({'services': {'one': {'volumes': [{'type': 'bind'}]}}},
                     {'services': {'one': {'privileged': True}}},
                     {'services': {'one': {}}, 'volumes': {'data': {'external': True}}}):
            with patch.object(cb, 'js', return_value=data):
                with self.assertRaises(ValueError): cb.config(self.record)

    @unittest.skipIf(os.name == 'nt', 'POSIX ownership/flock')
    def test_restore_failure_rolls_back_and_retains_safety(self):
        cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        (self.volume / 'value').write_text('live')
        original = cb.apply
        calls = []
        def apply(source, paths):
            calls.append(source)
            if len(calls) == 1:
                (self.volume / 'value').write_text('partial')
                raise OSError('injected')
            original(source, paths)
        with patch.object(cb, 'inspect', return_value=(self.data, self.containers, self.paths)), patch.object(cb, 'docker') as command, patch.object(cb, 'apply', side_effect=apply):
            with self.assertRaisesRegex(RuntimeError, 'rolled back'):
                cb.operate('fixture', 'restore', self.backup, True)
            self.assertEqual(command.call_args_list[-1].args, ('start', 'running'))
        self.assertEqual((self.volume / 'value').read_text(), 'live')
        self.assertEqual(len(list(self.base.glob('*safety*'))), 1)

    @unittest.skipIf(os.name == 'nt', 'POSIX flock')
    def test_rollback_failure_reports_retained_artifact_and_never_starts(self):
        cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        with patch.object(cb, 'inspect', return_value=(self.data, self.containers, self.paths)), patch.object(cb, 'docker') as command, patch.object(cb, 'apply', side_effect=OSError('failed')):
            with self.assertRaisesRegex(RuntimeError, 'project left stopped; manual intervention required'):
                cb.operate('fixture', 'restore', self.backup, True)
            self.assertEqual([call.args for call in command.call_args_list], [('stop', 'running')])
        safety = list(self.base.glob('*safety*'))
        self.assertEqual(len(safety), 1)
        self.assertTrue(cb.verify(safety[0], self.record, self.data, self.paths))

    def test_partial_restart_attempts_remaining_and_reports_failure(self):
        containers = self.containers + [{'Id': 'second', 'State': {'Running': True}}]
        calls = []
        def command(*args):
            calls.append(args)
            if args == ('start', 'running'):
                raise RuntimeError('injected restart failure')
        with patch.object(cb, 'docker', side_effect=command):
            with self.assertRaisesRegex(RuntimeError, '1 of 2 containers; project may be partially running'):
                with cb.stopped(containers):
                    pass
        self.assertEqual(calls, [('stop', 'running'), ('stop', 'second'), ('start', 'running'), ('start', 'second')])

    @unittest.skipIf(os.name == 'nt', 'POSIX flock')
    def test_invalid_restore_never_stops_and_safety_failure_never_applies(self):
        self.backup.write_bytes(b'corrupt')
        with patch.object(cb, 'inspect', return_value=(self.data, self.containers, self.paths)), patch.object(cb, 'docker') as command:
            with self.assertRaises(OSError): cb.operate('fixture', 'restore', self.backup, True)
            command.assert_not_called()
        self.backup.unlink()
        cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        with patch.object(cb, 'inspect', return_value=(self.data, self.containers, self.paths)), patch.object(cb, 'docker') as command, patch.object(cb, 'package', side_effect=OSError('safety')), patch.object(cb, 'apply') as apply:
            with self.assertRaises(OSError): cb.operate('fixture', 'restore', self.backup, True)
            apply.assert_not_called()
            self.assertEqual(command.call_args_list[-1].args, ('start', 'running'))

    @unittest.skipIf(os.name == 'nt', 'POSIX flock')
    def test_concurrent_operation_and_duplicate_registration_refused(self):
        with cb.lock('fixture'):
            with self.assertRaises(ValueError):
                with cb.lock('fixture'): pass
        with self.assertRaises(ValueError): cb.register('fixture', self.compose, True)

    @unittest.skipIf(os.name == 'nt', 'POSIX symlinks')
    def test_archive_symlink_rejected_without_publication(self):
        (self.volume / 'link').symlink_to(self.volume / 'value')
        with self.assertRaises(ValueError):
            cb.package(self.backup, self.record, self.data, self.containers, self.paths)
        self.assertFalse(self.backup.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
