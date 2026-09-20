import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

MODULE = Path(__file__).parents[1] / 'src/lib/docker_migration.py'
spec = importlib.util.spec_from_file_location('docker_migration', MODULE)
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)


class RestoreUnitTests(unittest.TestCase):
    def test_bind_targets_are_exact_absolute_and_absent(self):
        declaration = {'data': {'binds': {'/old': {'logical': 'app', 'path': 'data/binds/app'}}}}
        with tempfile.TemporaryDirectory() as root:
            target = str(Path(root).resolve() / 'app')
            self.assertEqual(dm.parse_bind_targets(['app=' + target], declaration), {'app': Path(target)})
            with self.assertRaises(ValueError):
                dm.parse_bind_targets([], declaration)

    def test_restore_contract_rejects_legacy_and_reserved_label(self):
        with self.assertRaisesRegex(ValueError, 'predates'):
            dm._restore_contract({'data': {'volumes': {}}, 'containers': []})

    def test_journal_uses_pending_then_created(self):
        journal = {'created': []}
        with mock.patch.object(dm, 'save_journal') as save:
            item = dm._begin_resource(Path('/fixed/journal.json'), journal, 'volume', 'v')
            self.assertEqual(item['status'], 'pending')
            dm._finish_resource(Path('/fixed/journal.json'), journal, item, 'v')
            self.assertEqual(item['status'], 'created')
            self.assertEqual(save.call_count, 2)

    def test_journal_fixed_path_and_private_validation(self):
        with mock.patch.object(dm, 'JOURNAL_BASE', Path('/fixed')):
            with self.assertRaisesRegex(ValueError, 'fixed'):
                dm._validate_journal_path(Path('/other/a' * 16) / 'journal.json')

    def test_rollback_never_deletes_image(self):
        transaction = 'a' * 32
        journal = {'owner': dm.JOURNAL_OWNER, 'transaction': transaction,
                   'created': [{'kind': 'image', 'name': 'sha256:x', 'id': 'sha256:x', 'status': 'created'}],
                   'state': 'failed'}
        with mock.patch.object(dm, 'load_journal', return_value=(Path('/journal'), journal)), \
             mock.patch.object(dm, 'save_journal'), mock.patch.object(dm, 'docker') as docker:
            dm.rollback(transaction)
            docker.assert_not_called()

    def test_rollback_refuses_unmarked_bind(self):
        transaction = 'b' * 32
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / 'bind'
            target.mkdir()
            journal = {'owner': dm.JOURNAL_OWNER, 'transaction': transaction,
                       'created': [{'kind': 'bind', 'name': str(target), 'id': str(target), 'status': 'created'}],
                       'state': 'failed'}
            with mock.patch.object(dm, 'load_journal', return_value=(Path('/journal'), journal)), \
                 mock.patch.object(dm, 'save_journal'):
                with self.assertRaises(RuntimeError):
                    dm.rollback(transaction)
                self.assertTrue(target.exists())

    def test_port_conflict_includes_protocol_and_wildcards(self):
        self.assertTrue(dm._port_conflicts(('0.0.0.0', '80', 'tcp'), ('127.0.0.1', '80', 'tcp')))
        self.assertTrue(dm._port_conflicts(('::', '80', 'udp'), ('::1', '80', 'udp')))
        self.assertFalse(dm._port_conflicts(('0.0.0.0', '80', 'tcp'), ('127.0.0.1', '80', 'udp')))
        self.assertFalse(dm._port_conflicts(('127.0.0.1', '80', 'tcp'), ('127.0.0.2', '80', 'tcp')))

    def test_transaction_label_is_last(self):
        network = {'driver': 'bridge', 'internal': False, 'attachable': False, 'enable_ipv6': False,
                   'labels': {'z': '1'}, 'options': {}, 'ipam': {}, 'name': 'n'}
        with mock.patch.object(dm, 'docker', return_value=b'id') as docker:
            dm._network_create(network, 'tx')
            args = docker.call_args.args
            reserved = ('--label', dm.TRANSACTION_LABEL + '=tx')
            self.assertEqual(args[args.index('--label', args.index('--label') + 1):args.index('--label', args.index('--label') + 1) + 2], reserved)

    def test_ipv6_publish_uses_brackets(self):
        self.assertEqual(dm._publish_spec('2001:db8::1', '8443', '443/tcp'), '[2001:db8::1]:8443:443/tcp')
        self.assertEqual(dm._publish_spec('127.0.0.1', '8080', '80/tcp'), '127.0.0.1:8080:80/tcp')

    def test_pending_missing_resource_is_not_adopted(self):
        with mock.patch.object(dm, '_existing', return_value=False), mock.patch.object(dm, 'js') as inspect:
            self.assertIsNone(dm._resource_owned('volume', 'missing', 'tx'))
            inspect.assert_not_called()

    def test_image_rollback_removes_only_new_declared_tags_and_ids(self):
        journal = {'image_load': {'before': {'ids': ['sha256:old'], 'tags': ['repo:old']},
                                  'declared_ids': ['sha256:new'],
                                  'declared_tags': ['repo:new', 'repo:old'], 'rolled_back': False}}
        snapshots = [
            {'ids': ['sha256:old', 'sha256:new'], 'tags': ['repo:old', 'repo:new', 'other:new']},
            {'ids': ['sha256:old', 'sha256:new'], 'tags': ['repo:old', 'other:new']},
        ]
        with mock.patch.object(dm, '_image_snapshot', side_effect=snapshots), \
             mock.patch.object(dm, 'docker') as docker:
            dm._rollback_images(journal)
            self.assertEqual(docker.call_args_list,
                             [mock.call('image', 'rm', 'repo:new'), mock.call('image', 'rm', 'sha256:new')])
            self.assertTrue(journal['image_load']['rolled_back'])

    def test_bind_copy_uses_pinned_root_fd(self):
        item = {'data_status': 'pending'}
        journal = {}
        manager = mock.MagicMock()
        manager.__enter__.return_value = (10, 'bind', 11)
        pinned = mock.Mock(st_dev=1, st_ino=2)
        with mock.patch.object(dm, '_bind_fds', return_value=manager) as bind_fds, \
             mock.patch.object(dm, '_marker_owned_fd', return_value=True), \
             mock.patch.object(dm.os, 'fstat', return_value=pinned), \
             mock.patch.object(dm.os, 'stat', return_value=pinned), \
             mock.patch.object(dm, '_clear_fd') as clear_fd, \
             mock.patch.object(dm, '_copy_tree_fd') as copy_fd, \
             mock.patch.object(dm, 'save_journal'):
            dm._copy_bind_data(Path('/journal'), journal, item, Path('/stage'), Path('/parent/bind'), 'tx')
            bind_fds.assert_called_once_with(Path('/parent/bind'))
            clear_fd.assert_called_once_with(11, preserve=(dm.BIND_MARKER,))
            copy_fd.assert_called_once_with(Path('/stage'), 11)
            self.assertEqual(item['data_status'], 'created')

    def test_copy_tree_restores_root_metadata_and_refuses_existing_child(self):
        with tempfile.TemporaryDirectory() as root:
            source, target = Path(root) / 'source', Path(root) / 'target'
            source.mkdir(mode=0o750); target.mkdir()
            (source / 'file').write_text('x')
            with mock.patch.object(dm.os, 'chown', create=True):
                dm._copy_tree(source, target)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), stat.S_IMODE(source.stat().st_mode))
            with mock.patch.object(dm.os, 'chown', create=True):
                with self.assertRaisesRegex(ValueError, 'existing'):
                    dm._copy_tree(source, target)


if __name__ == '__main__':
    unittest.main()
