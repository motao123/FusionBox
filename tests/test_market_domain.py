import unittest
import json
import tempfile
from unittest.mock import patch
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_domain as d


class DomainValidation(unittest.TestCase):
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
