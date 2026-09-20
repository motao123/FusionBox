import unittest
import json
import tempfile
from unittest.mock import patch
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_domain as d


class DomainValidation(unittest.TestCase):
    @unittest.skipIf(sys.platform == 'win32', 'POSIX file permissions')
    def test_tls_key_permissions_links_and_paths(self):
        import os
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / 'key.pem'
            key.write_text('not a secret fixture')
            os.chmod(key, 0o600)
            self.assertEqual(d.market_tls.file_path(str(key), True), str(key))
            os.chmod(key, 0o644)
            with self.assertRaises(ValueError): d.market_tls.file_path(str(key), True)
            os.chmod(key, 0o600)
            link = Path(folder) / 'linked.pem'
            link.symlink_to(key)
            with self.assertRaises(ValueError): d.market_tls.file_path(str(link), True)
            with self.assertRaises(ValueError): d.market_tls.file_path(str(key) + ';inject', True)

    def test_rejects_invalid_and_accepts_dns(self):
        for value in ('localhost', 'EXAMPLE.COM', '*.example.com', 'http://example.com', '127.0.0.1', 'a..example.com'):
            with self.assertRaises(ValueError): d.validate(value)
        self.assertEqual(d.validate('app.example.com'), 'app.example.com')

    def test_render_is_http_only_and_localhost_upstream(self):
        record = {'project': 'fb-market-nginx', 'market': {'token': 'a' * 32, 'port': 8080,
                  'domain': {'name': 'app.example.com', 'listen': 18080, 'mode': 'http-only', 'enabled': True}}}
        text = d.render(record)
        self.assertIn('server_name app.example.com;', text)
        self.assertIn('proxy_pass http://127.0.0.1:8080;', text)
        self.assertNotIn('ssl_certificate', text)
        self.assertNotIn('443', text)

    def test_rejects_listen_collision_with_upstream(self):
        record = {'project': 'fb-market-nginx', 'market': {'token': 'a' * 32, 'port': 8080,
                  'domain': {'name': 'app.example.com', 'listen': 8080, 'mode': 'http-only', 'enabled': True}}}
        with self.assertRaises(ValueError): d.render(record)


class DomainTransactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.conf = self.base / 'conf.d'
        self.conf.mkdir()
        self.addCleanup(patch.stopall)
        patch.object(d, 'CONF', self.conf).start()
        patch.object(d.cb, 'BASE', self.base).start()
        # Windows paths are not accepted by the production path validator.
        self.target = self.conf / 'mapping.conf'
        patch.object(d, 'path', return_value=self.target).start()
        self.record = {'project': 'fixture', 'market': {'token': 'a' * 32, 'port': 8080}}
        self.registry = self.base / 'fixture.json'
        self.registry.write_text(json.dumps(self.record))
        self.nginx = patch.object(d, 'nginx', return_value='include ' + str(self.conf) + '/*.conf;').start()

    def test_tls_invalid_material_preserves_state(self):
        before = self.registry.read_bytes()
        with patch.object(d.market_tls, 'validate', side_effect=ValueError('invalid PEM')):
            with self.assertRaises(ValueError):
                d.change(self.registry, self.record, 'test.local', tls={'cert': '/tmp/cert', 'key': '/tmp/key', 'listen': 443, 'redirect': True})
        self.assertEqual(before, self.registry.read_bytes())
        self.assertFalse(self.target.exists())
        self.nginx.assert_not_called()

    def test_tls_suspend_retain_and_disable(self):
        tls = {'cert': '/tmp/cert', 'key': '/tmp/key', 'listen': 443, 'redirect': True}
        with patch.object(d.market_tls, 'validate'):
            d.change(self.registry, self.record, 'test.local', tls=tls)
            record = json.loads(self.registry.read_text())
            self.assertIn('return 308 https://test.local$request_uri;', self.target.read_text())
            d.change(self.registry, record, 'test.local', enabled=False)
            suspended = json.loads(self.registry.read_text())
            self.assertEqual(suspended['market']['domain']['tls'], tls)
            self.assertEqual(self.target.read_text().count('return 503;'), 2)
            d.change(self.registry, suspended, 'test.local', tls=None)
            self.assertNotIn('ssl_certificate', self.target.read_text())

    def test_tls_double_reload_failure_retains_original(self):
        tls = {'cert': '/tmp/cert', 'key': '/tmp/key', 'listen': 443, 'redirect': True}
        with patch.object(d.market_tls, 'validate'):
            d.change(self.registry, self.record, 'test.local', tls=tls)
        record = json.loads(self.registry.read_text())
        before = self.registry.read_bytes(), self.target.read_bytes()
        self.nginx.side_effect = [self.nginx.return_value, '', '', RuntimeError('reload'), '', RuntimeError('rollback')]
        with self.assertRaisesRegex(RuntimeError, 'AND rollback failed'):
            d.change(self.registry, record, 'test.local', tls=None)
        self.assertEqual(before, (self.registry.read_bytes(), self.target.read_bytes()))
        self.assertTrue((self.base / 'fixture.domain-recovery.json').exists())

    def prepare_refresh(self):
        tls = {'cert': '/tmp/cert', 'key': '/tmp/key', 'listen': 443, 'redirect': True}
        with patch.object(d.market_tls, 'validate'):
            d.change(self.registry, self.record, 'test.local', tls=tls)
        self.record = json.loads(self.registry.read_text())
        self.nginx.reset_mock()
        patch.object(d.market_tls, 'validate', return_value='2027-01-01T00:00:00+00:00').start()
        patch.object(d.market_tls, 'fingerprint', return_value='a' * 64).start()
        self.probe = patch.object(d.market_tls, 'wait_served').start()
        return self.base / 'fixture.tls-refresh.json'

    def test_refresh_preserves_config_and_registry(self):
        journal = self.prepare_refresh()
        before = self.registry.read_bytes(), self.target.read_bytes()
        d.refresh(self.registry, self.record)
        self.assertEqual(before, (self.registry.read_bytes(), self.target.read_bytes()))
        self.assertFalse(journal.exists())
        self.probe.assert_called_once_with('test.local', 443, 'a' * 64)

    def test_refresh_invalid_or_unreadable_input_never_reloads(self):
        journal = self.prepare_refresh()
        for error in (ValueError('expired'), ValueError('wrong key'), PermissionError('read failure')):
            with patch.object(d.market_tls, 'validate', side_effect=error):
                with self.assertRaises(type(error)): d.refresh(self.registry, self.record)
        self.nginx.assert_not_called()
        self.assertFalse(journal.exists())

    def test_refresh_double_failure_then_explicit_retry(self):
        journal = self.prepare_refresh()
        before = self.registry.read_bytes(), self.target.read_bytes()
        for unused in range(2):
            self.nginx.side_effect = ['', RuntimeError('reload')]
            with self.assertRaisesRegex(RuntimeError, 'runtime state unknown'):
                d.refresh(self.registry, self.record)
            self.assertTrue(journal.exists())
            self.assertEqual(before, (self.registry.read_bytes(), self.target.read_bytes()))
        self.nginx.side_effect = None
        d.refresh(self.registry, self.record)
        self.assertFalse(journal.exists())

    def test_refresh_async_failure_retains_journal(self):
        journal = self.prepare_refresh()
        self.probe.side_effect = RuntimeError('old certificate still served')
        with self.assertRaisesRegex(RuntimeError, 'No certificate/key files copied or restored'):
            d.refresh(self.registry, self.record)
        self.assertTrue(journal.exists())

    def test_refresh_rejects_unknown_journal_and_changed_input(self):
        journal = self.prepare_refresh()
        journal.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'Unknown'):
            d.refresh(self.registry, self.record)
        self.nginx.assert_not_called()
        journal.unlink()
        with patch.object(d.market_tls, 'fingerprint', side_effect=['a', 'b']):
            with self.assertRaisesRegex(RuntimeError, 'runtime state unknown'):
                d.refresh(self.registry, self.record)
        self.assertTrue(journal.exists())
        self.assertEqual(self.nginx.call_count, 1)  # validation only, no reload

    def test_status_reports_runtime_mismatch_and_unavailable(self):
        import io
        self.prepare_refresh()
        for result in ('b' * 64, OSError('offline')):
            output = io.StringIO()
            with patch.object(d.market_tls, 'served', side_effect=result if isinstance(result, Exception) else None,
                              return_value=result), patch('sys.stdout', output):
                d.status(self.record)
            self.assertIn('active certificate unknown' if isinstance(result, Exception) else 'DIFFERS', output.getvalue())

    def test_remaining_days_boundaries(self):
        import datetime
        now = datetime.datetime(2026, 9, 18, tzinfo=datetime.timezone.utc)
        for seconds, days in ((86400, 1), (86399, 0), (1, 0), (0, 0), (-1, -1)):
            expiry = (now + datetime.timedelta(seconds=seconds)).isoformat()
            self.assertEqual(d.market_tls.remaining_days(expiry, now), days)

    def test_refresh_wait_is_bounded_and_retries_socket_failure(self):
        with patch.object(d.market_tls, 'served', side_effect=[OSError(), 'old', 'new']), patch.object(d.market_tls.time, 'sleep'):
            d.market_tls.wait_served('test.local', 443, 'new')
        with patch.object(d.market_tls, 'served', return_value='old') as probe, patch.object(d.market_tls.time, 'sleep'):
            with self.assertRaises(RuntimeError): d.market_tls.wait_served('test.local', 443, 'new')
            self.assertEqual(probe.call_count, 20)

    def test_success_and_remove(self):
        d.change(self.registry, self.record, 'app.example.com')
        record = json.loads(self.registry.read_text())
        self.assertEqual(self.target.read_text(), d.render(record))
        self.assertEqual(self.nginx.call_args_list[1].args[:2], ('-t', '-c'))
        d.change(self.registry, record)
        self.assertFalse(self.target.exists())
        self.assertEqual(json.loads(self.registry.read_text()), self.record)

    def test_unowned_file_preserved(self):
        self.target.write_text('unowned')
        with self.assertRaisesRegex(ValueError, 'Unowned'):
            d.change(self.registry, self.record, 'app.example.com')
        self.assertEqual(self.target.read_text(), 'unowned')
        self.nginx.assert_not_called()

    def test_collision_before_write(self):
        self.nginx.return_value += '\nserver_name *.example.com;'
        with self.assertRaisesRegex(ValueError, 'collides'):
            d.change(self.registry, self.record, 'app.example.com')
        self.assertFalse(self.target.exists())

    def test_reload_failure_rolls_back(self):
        self.nginx.side_effect = [self.nginx.return_value, '', '', RuntimeError('reload'), '', '']
        with self.assertRaisesRegex(RuntimeError, 'previous configuration restored'):
            d.change(self.registry, self.record, 'app.example.com')
        self.assertFalse(self.target.exists())
        self.assertEqual(json.loads(self.registry.read_text()), self.record)
        self.assertFalse((self.base / 'fixture.domain-recovery.json').exists())

    def test_double_failure_retains_journal(self):
        self.nginx.side_effect = [self.nginx.return_value, '', '', RuntimeError('reload'), '', RuntimeError('reload')]
        with self.assertRaisesRegex(RuntimeError, 'AND rollback failed'):
            d.change(self.registry, self.record, 'app.example.com')
        self.assertTrue((self.base / 'fixture.domain-recovery.json').exists())
        self.assertEqual(json.loads(self.registry.read_text()), self.record)


if __name__ == '__main__':
    unittest.main()
