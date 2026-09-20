import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
if sys.platform != 'win32':
    import cluster_nodes as c


@unittest.skipIf(sys.platform == 'win32', 'Linux flock and POSIX permissions required')
class ClusterNodes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.base = self.root / 'cluster'
        self.base.mkdir(mode=0o700)
        self.old = self.base / 'nodes.conf'
        self.old.write_text('first|root@example.test|22\n')
        self.old.chmod(0o600)
        self.source = self.root / 'source.json'
        self.item = {'id': 'second', 'user': 'deploy', 'host': '2001:db8::1', 'port': 2222}
        self.source_data([self.item])

    def source_data(self, items):
        self.source.write_text(json.dumps({'format': 'fusionbox-cluster-nodes', 'version': 1, 'nodes': items}))
        self.source.chmod(0o600)

    def run_op(self, action='import', **kwargs):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            c.operate(self.base, action, file=self.source, **kwargs)
        return output.getvalue()

    def test_dry_run_and_roundtrip_fields(self):
        before = self.old.read_bytes(), self.source.read_bytes()
        self.assertIn('Dry-run', self.run_op())
        self.assertEqual(before, (self.old.read_bytes(), self.source.read_bytes()))
        self.run_op(confirm=True)
        self.assertEqual(c.legacy(self.old)[1], self.item)
        export = self.root / 'export.json'
        c.operate(self.base, 'export', file=export)
        self.assertEqual(c.incoming(export), c.legacy(self.old))
        self.assertEqual(export.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.old.stat().st_mode & 0o777, 0o600)
        self.assertEqual(before[1], self.source.read_bytes())

    def test_conflict_even_identical_no_overwrite(self):
        self.source_data(c.legacy(self.old))
        before = self.old.read_bytes()
        for confirm in (False, True):
            with self.assertRaisesRegex(ValueError, 'Conflicting'):
                self.run_op(confirm=confirm)
            self.assertEqual(before, self.old.read_bytes())

    def test_duplicate_nodes_and_properties(self):
        self.source_data([self.item, self.item])
        with self.assertRaisesRegex(ValueError, 'Duplicate'): self.run_op(confirm=True)
        self.source.write_text('{"version":1,"version":1}')
        with self.assertRaisesRegex(ValueError, 'Duplicate'): self.run_op()

    def test_malformed_and_unknown_schema_unchanged(self):
        before = self.old.read_bytes()
        for value in ('not JSON', '[]', '{"format":"fusionbox-cluster-nodes","version":2,"nodes":[]}',
                      '{"format":"fusionbox-cluster-nodes","version":true,"nodes":[]}'):
            self.source.write_text(value)
            with self.assertRaises(ValueError): self.run_op(confirm=True)
            self.assertEqual(before, self.old.read_bytes())

    def test_strict_fields_and_credentials_rejected(self):
        for field in ('password', 'key', 'command', 'identity_file'):
            self.source_data([dict(self.item, **{field: 'secret'})])
            with self.assertRaises(ValueError): self.run_op(confirm=True)
        for port in (True, '22', 0, -1, 65536, 22.0):
            self.source_data([dict(self.item, port=port)])
            with self.assertRaises(ValueError): self.run_op(confirm=True)

    def test_injection_payloads_never_execute(self):
        sentinel = self.root / 'executed'
        before = self.old.read_bytes()
        for field in ('id', 'user', 'host'):
            for value in ('$(touch ' + str(sentinel) + ')', '`id`', '-oProxyCommand=id', 'a\nb', 'a|b', 'x;id', 'a b'):
                self.source_data([dict(self.item, **{field: value})])
                with self.assertRaises(ValueError): self.run_op(confirm=True)
        self.assertFalse(sentinel.exists())
        self.assertEqual(before, self.old.read_bytes())

    def test_host_and_ipv6_validation(self):
        for host in ('localhost', 'node.example', '192.0.2.1', '::1', '2001:db8::1'):
            self.assertEqual(c.node(dict(self.item, host=host))['host'], host)
        for host in ('999.1.1.1', '[::1]', 'fe80::1%eth0', 'a..b', '.foo', 'foo.', '-foo', 'foo/bar', 'a@b'):
            with self.assertRaises(ValueError): c.node(dict(self.item, host=host))

    def test_export_refuses_existing_and_symlinks(self):
        before = self.source.read_bytes()
        with self.assertRaises(FileExistsError): self.run_op('export')
        self.assertEqual(before, self.source.read_bytes())
        link = self.root / 'link'
        link.symlink_to(self.base, target_is_directory=True)
        with self.assertRaises(ValueError): c.operate(self.base, 'export', file=link / 'out.json')
        self.source.unlink(); self.source.symlink_to(self.old)
        with self.assertRaises(ValueError): self.run_op(confirm=True)
        with self.assertRaises(ValueError): self.run_op('export')

    def test_permissions_hardlinks_and_owner(self):
        self.source.chmod(0o644)
        with self.assertRaises(ValueError): self.run_op()
        self.source.chmod(0o600)
        extra = self.root / 'hardlink'; os.link(self.source, extra)
        with self.assertRaises(ValueError): self.run_op()
        extra.unlink()
        with patch.object(c.os, 'geteuid', return_value=os.geteuid() + 1):
            with self.assertRaises(ValueError): self.run_op()

    def test_failed_atomic_write_preserves_old_and_source(self):
        before = self.old.read_bytes(), self.source.read_bytes()
        with patch.object(c.os, 'replace', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError): self.run_op(confirm=True)
        self.assertEqual(before, (self.old.read_bytes(), self.source.read_bytes()))
        self.assertFalse(list(self.base.glob('.nodes-*')))
        with self.assertRaisesRegex(ValueError, 'exceeds'):
            c.write(self.old, 'x' * (c.LIMIT + 1))
        self.assertEqual(before[0], self.old.read_bytes())

    def test_lock_shared_by_import_add_remove_export(self):
        before = self.old.read_bytes()
        with c.locked(self.base):
            for action in ('import', 'add', 'remove', 'export'):
                with self.assertRaises(BlockingIOError):
                    self.run_op(action, confirm=True, item=self.item, name='first')
        self.assertEqual(before, self.old.read_bytes())

    def test_legacy_migration_is_explicit_and_rejects_bad_rows(self):
        before = self.old.read_bytes()
        self.run_op('list')
        self.assertEqual(before, self.old.read_bytes())
        for row in ('x|host|22\n', 'x|-oProxyCommand=id|22\n', 'x|root@host|22|password\n',
                    'x|root@host|22\nx|root@other|23\n'):
            self.old.write_text(row)
            with self.assertRaises(ValueError): self.run_op(confirm=True)
            self.assertEqual(row, self.old.read_text())

    def test_add_remove_exact_id_and_duplicate_rejection(self):
        self.run_op('add', item=self.item)
        with self.assertRaisesRegex(ValueError, 'Duplicate'): self.run_op('add', item=self.item)
        with self.assertRaisesRegex(ValueError, 'Unknown'): self.run_op('remove', name='irst')
        self.run_op('remove', name='first')
        self.assertEqual(c.legacy(self.old), [self.item])

    def test_cli_snapshot_and_ipv6_scp_without_network(self):
        self.run_op(confirm=True)
        repo = Path(__file__).resolve().parents[1]
        script = '''source "$1/src/modules/cluster.sh"
FUSION_SRC="$1/src"; CLUSTER_DIR="$2"
_require_root() { :; }; msg_title() { :; }; msg() { :; }; pause() { :; }
msg_info() { :; }; msg_ok() { :; }; _log_write() { :; }
scp() { printf '%s\\n' "$@"; }
cluster_sync
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(repo), str(self.base)],
                                input=str(self.source) + '\n/tmp/target\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('deploy@[2001:db8::1]:/tmp/target', result.stdout)
        self.old.write_text('unsafe|-oProxyCommand=id|22\n')
        result = subprocess.run(['bash', '-c', script, 'test', str(repo), str(self.base)],
                                input='', text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('/tmp/target', result.stdout)


if __name__ == '__main__':
    unittest.main()
