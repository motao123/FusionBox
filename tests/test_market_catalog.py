"""Local declarative managed catalog tests; intentionally ignored by git."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_apps as apps
import market_catalog as catalog


class Catalog(unittest.TestCase):
    def test_builtin_strict_and_privilege_visible(self):
        value, source = catalog.load(Path(tempfile.gettempdir()))
        self.assertEqual(source, 'builtin')
        self.assertFalse(value['apps']['ntfy-v1']['high_privilege'])
        privileged = value['apps']['docker-admin-example']
        self.assertTrue(privileged['high_privilege'])
        self.assertTrue(privileged['revoked'])
        changed = json.loads(catalog.BUILTIN.read_text())
        changed['apps'][0]['unknown'] = True
        with self.assertRaisesRegex(ValueError, 'fields'):
            catalog.parse(json.dumps(changed))

    def test_remote_pin_cache_and_builtin_fallback(self):
        body = catalog.BUILTIN.read_bytes()
        digest = hashlib.sha256(body).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            value, source = catalog.load(root, 'https://catalog.example/v1.json', digest, opener=lambda _: body)
            self.assertEqual((source, value['catalog_id']), ('remote', 'fusionbox-builtin'))
            value, source = catalog.load(root, 'https://catalog.example/v1.json', digest,
                                         opener=lambda _: (_ for _ in ()).throw(OSError('offline')))
            self.assertEqual(source, 'cache')
            _, source = catalog.load(root, 'https://other.example/v1.json', digest,
                                     opener=lambda _: (_ for _ in ()).throw(OSError('offline')))
            self.assertTrue(source.startswith('builtin-fallback:'))
        with self.assertRaisesRegex(ValueError, 'HTTPS'):
            catalog.load(Path(tempfile.gettempdir()), 'http://catalog.example/v1.json', digest,
                         opener=lambda _: body)

    def test_manifest_compose_is_localhost_and_owned(self):
        value, _ = catalog.load(Path(tempfile.gettempdir()))
        spec = value['apps']['ntfy-v1']
        record = {'project': 'fb-market-ntfy-v1', 'compose': '/private/compose',
                  'market': {'owner': apps.OWNER, 'app': 'ntfy-v1', 'token': 'a' * 32,
                             'state': 'installing', 'catalog_app': spec,
                             'catalog_digest': catalog.app_digest(spec)}}
        document = apps.document(record)
        service = document['services']['app']
        self.assertEqual(service['ports'], ['127.0.0.1:8091:8080/tcp'])
        self.assertEqual(service['cap_drop'], ['ALL'])
        self.assertNotIn('/var/run/docker.sock:/var/run/docker.sock', service['volumes'])

    def test_revoked_and_exact_privilege_confirmation(self):
        value, _ = catalog.load(Path(tempfile.gettempdir()))
        with patch.object(apps, 'RUNTIME_CATALOG', value), patch.object(apps.cb, 'docker') as docker:
            with self.assertRaisesRegex(ValueError, 'revoked'):
                apps.operate('install', 'docker-admin-example', accepted=True)
            docker.assert_not_called()
        privileged = json.loads(catalog.BUILTIN.read_text())
        privileged['apps'][1]['revoked'] = False
        value = catalog.parse(json.dumps(privileged))
        with patch.object(apps, 'RUNTIME_CATALOG', value), patch.object(apps.cb, 'docker') as docker:
            with self.assertRaisesRegex(ValueError, 'exact --risk-ack'):
                apps.operate('install', 'docker-admin-example', accepted=True)
            docker.assert_not_called()

    def test_declared_udp_multi_service_nas_and_device_parse(self):
        value = json.loads(catalog.BUILTIN.read_text())
        app = value['apps'][0]
        app['id'] = 'media-stack'
        app['nas_path'] = True
        app['services'][0]['ports'].append({'published': 8093, 'target': 8093, 'protocol': 'udp'})
        app['services'][0]['binds'] = [{'source': '{nas_path}/media', 'target': '/media', 'read_only': True}]
        second = json.loads(json.dumps(app['services'][0]))
        second['id'] = 'worker'
        second['ports'] = []
        second['binds'] = []
        second['devices'] = [{'source': '/dev/dri', 'target': '/dev/dri', 'permissions': 'rw'}]
        app['services'].append(second)
        app['high_privilege'] = True
        app['risk_acknowledgement'] = 'I ACCEPT HIGH PRIVILEGE: media-stack'
        parsed = catalog.parse(json.dumps(value))
        self.assertEqual(len(parsed['apps']['media-stack']['services']), 2)


if __name__ == '__main__':
    unittest.main()
