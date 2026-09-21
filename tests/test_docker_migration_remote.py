"""Failure matrix for the docker-migration remote orchestration (no real SSH)."""
import contextlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import docker_migration_remote as dmr

NODE = {'id': 'node2', 'user': 'root', 'host': '127.0.0.1', 'port': 2222}
TX = 'a' * 32


def completed(returncode=0, stdout='', stderr=''):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


class RemoteOrchestration(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='fb-remote-'))
        self.addCleanup(self._cleanup)
        self.bundle = self.root / 'app.tar.gz'
        self.bundle.write_bytes(b'bundle')
        self.bundle.chmod(0o600)
        self.key = self.root / 'migrate'
        self.key.write_bytes(b'key')
        self.key.chmod(0o600)
        self.hosts = self.root / 'known_hosts'
        self.hosts.write_text('')
        self.hosts.chmod(0o600)
        # SimpleNamespace, not Mock: Mock(name=...) reserves `name` for the mock's
        # repr name, which silently leaves args.name as a child attribute and
        # breaks the archive-name validation under test.
        self.args = types.SimpleNamespace(
            node='node2', bundle=str(self.bundle), name='app.tar.gz',
            key=str(self.key), known_hosts=str(self.hosts),
            remote_src='/etc/fusionbox/src',
            remote_store='/var/lib/fusionbox/docker-migration-store',
            directory=str(self.root), health_timeout=120,
            transfer_timeout=300, dry_run=False, json_output=False)
        self.transfer = patch.object(dmr.archive_transfer, 'run').start()
        self.inspect = patch.object(dmr.docker_migration, 'inspect_bundle', return_value={
            'containers': [{'name': 'web'}, {'name': 'db'}]}).start()
        @contextlib.contextmanager
        def fake_locked(_base):
            yield self.root / 'nodes.conf'
        patch.object(dmr.cluster_nodes, 'locked', fake_locked).start()
        patch.object(dmr.cluster_nodes, 'legacy', return_value=[NODE]).start()
        self.addCleanup(patch.stopall)

    def _cleanup(self):
        import shutil
        shutil.rmtree(self.root, ignore_errors=True)

    # ---- scripted ssh ------------------------------------------------------
    def gate(self, migration='yes', store='700'):
        return completed(0, stdout=(
            'python3=3.12\ndocker=27.0\nostype=linux\narch=x86_64\n'
            'migration=%s\nstore=%s\n' % (migration, store)))

    def script_ssh(self, responses):
        """responses: list of (predicate, CompletedProcess) tried in order."""
        def fake(_node, _hosts, _key, command, timeout=120):
            for predicate, result in responses:
                if predicate(command):
                    return result
            raise AssertionError('unexpected remote command: ' + command)
        return fake

    def test_unknown_node_refused_before_any_ssh(self):
        with patch.object(dmr.cluster_nodes, 'legacy', return_value=[]):
            with patch.object(dmr, '_ssh', side_effect=AssertionError('no ssh expected')):
                with self.assertRaisesRegex(ValueError, '未知节点'):
                    dmr.run(self.args)
        self.transfer.assert_not_called()

    def test_invalid_archive_name_refused(self):
        self.args.name = 'bad name.tar.gz'
        with self.assertRaisesRegex(ValueError, '远端名'):
            dmr.run(self.args)

    def test_relative_known_hosts_refused(self):
        self.args.known_hosts = 'known_hosts'
        with self.assertRaisesRegex(ValueError, '--known-hosts'):
            dmr.run(self.args)

    def test_gate_failure_reports_missing_component(self):
        with patch.object(dmr, '_ssh', return_value=completed(1, stderr='docker: command not found')):
            with self.assertRaisesRegex(RuntimeError, '环境门禁失败'):
                dmr.run(self.args)
        self.transfer.assert_not_called()

    def test_gate_without_fusionbox_refused(self):
        with patch.object(dmr, '_ssh', return_value=self.gate(migration='no')):
            with self.assertRaisesRegex(RuntimeError, '未安装 FusionBox'):
                dmr.run(self.args)
        self.transfer.assert_not_called()

    def test_gate_with_wrong_store_mode_refused(self):
        with patch.object(dmr, '_ssh', return_value=self.gate(store='755')):
            with self.assertRaisesRegex(RuntimeError, '0700'):
                dmr.run(self.args)
        self.transfer.assert_not_called()

    def test_dry_run_touches_nothing_on_target(self):
        self.args.dry_run = True
        with patch.object(dmr, '_ssh', return_value=self.gate()) as ssh:
            summary = dmr.run(self.args)
        self.assertEqual(summary['result'], 'dry-run')
        self.assertEqual(summary['steps'], ['gate'])
        self.transfer.assert_not_called()
        # Only the read-only gate ran.
        self.assertEqual(ssh.call_count, 1)

    def test_transfer_failure_stops_before_preflight(self):
        self.transfer.side_effect = RuntimeError('SSH operation failed; source retained')
        with patch.object(dmr, '_ssh', return_value=self.gate()):
            with self.assertRaisesRegex(RuntimeError, 'source retained'):
                dmr.run(self.args)

    def test_target_preflight_rejection_keeps_target_clean(self):
        with patch.object(dmr, '_ssh', side_effect=self.script_ssh([
                (lambda c: 'python3=' in c, self.gate()),
                (lambda c: ' preflight ' in c, completed(1, stderr='Declared image RepoTag already exists on target')),
        ])):
            report = Mock()
            with patch.object(dmr, '_report', report):
                with self.assertRaisesRegex(RuntimeError, 'preflight 拒绝'):
                    dmr.run(self.args)
        self.assertEqual(self.transfer.call_count, 1)
        summary = report.call_args.args[0]
        self.assertEqual(summary['result'], 'preflight-rejected')
        self.assertTrue(summary['target_clean'])
        # The rejection happened before restore: no rollback may be attempted.
        self.assertNotIn('rollback', summary)

    def test_restore_failure_triggers_rollback_with_transaction(self):
        rollbacks = []
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(1, stderr='Restore failed; use rollback or resume with transaction ' + TX)
            if 'journal.json' in command:
                return completed(0, stdout='RuntimeError: boom')
            if ' rollback ' in command:
                rollbacks.append(command)
                return completed(0)
            raise AssertionError('unexpected: ' + command)
        with patch.object(dmr, '_ssh', side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, 'restore 失败'):
                dmr.run(self.args)
        self.assertEqual(len(rollbacks), 1)
        self.assertIn(TX, rollbacks[0])

    def test_restore_failure_with_failed_rollback_requires_recovery(self):
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(1, stderr='Restore failed; use rollback or resume with transaction ' + TX)
            if 'journal.json' in command:
                return completed(0, stdout='RuntimeError: boom')
            if ' rollback ' in command:
                return completed(1, stderr='Rollback failed')
            raise AssertionError('unexpected: ' + command)
        report = Mock()
        with patch.object(dmr, '_ssh', side_effect=fake):
            with patch.object(dmr, '_report', report):
                with self.assertRaises(RuntimeError):
                    dmr.run(self.args)
        summary = report.call_args.args[0]
        self.assertTrue(summary['recovery_required'])
        self.assertIn('rollback ' + TX, summary['action_required'])

    def test_restore_success_without_transaction_is_a_failure(self):
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(0, stdout='Restore complete without transaction id')
            if ' rollback ' in command:
                return completed(0)
            raise AssertionError('unexpected: ' + command)
        with patch.object(dmr, '_ssh', side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, '未返回事务 ID'):
                dmr.run(self.args)

    def test_unhealthy_containers_trigger_rollback(self):
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(0, stdout='Restore complete. Transaction: ' + TX)
            if 'for n in' in command:
                return completed(0, stdout='web=running\ndb=stopped\n')
            if ' rollback ' in command:
                return completed(0)
            raise AssertionError('unexpected: ' + command)
        with patch.object(dmr, '_ssh', side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, '健康校验未通过'):
                dmr.run(self.args)

    def test_success_path_reports_migrated(self):
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(0, stdout='Restore complete. Transaction: ' + TX)
            if 'for n in' in command:
                return completed(0, stdout='web=running\ndb=running\n')
            raise AssertionError('unexpected: ' + command)
        with patch.object(dmr, '_ssh', side_effect=fake):
            summary = dmr.run(self.args)
        self.assertEqual(summary['result'], 'migrated')
        self.assertEqual(summary['steps'], ['gate', 'transfer', 'preflight', 'restore', 'health'])
        self.assertEqual(summary['containers_state'], {'web': 'running', 'db': 'running'})
        self.transfer.assert_called_once()
        self.assertEqual(self.transfer.call_args.args[0].kind, 'docker-v1')
        self.assertEqual(self.transfer.call_args.args[0].sha256,
                         __import__('hashlib').sha256(b'bundle').hexdigest())

    def test_json_output_single_machine_readable_line(self):
        import io
        def fake(_node, _hosts, _key, command, timeout=120):
            if 'python3=' in command:
                return self.gate()
            if ' preflight ' in command:
                return completed(0, stdout='Preflight passed')
            if ' restore ' in command:
                return completed(0, stdout='Restore complete. Transaction: ' + TX)
            if 'for n in' in command:
                return completed(0, stdout='web=running\ndb=running\n')
            raise AssertionError('unexpected: ' + command)
        self.args.json_output = True
        out = io.StringIO()
        with patch.object(sys, 'stdout', out):
            with patch.object(dmr, '_ssh', side_effect=fake):
                dmr.run(self.args)
        lines = [line for line in out.getvalue().splitlines() if line.strip()]
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload['result'], 'migrated')
        self.assertEqual(payload['transaction'], TX)


if __name__ == '__main__':
    unittest.main()
