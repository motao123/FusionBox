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


class MultiContainerFields(unittest.TestCase):
    """New declarative fields: every one is a capability, so every one is checked."""

    def document(self, **service):
        base = {'id': 'app', 'image': 'nginx@sha256:' + 'a' * 64, 'ports': [], 'volumes': [],
                'binds': [], 'devices': [], 'network_mode': 'bridge', 'docker_socket': False,
                'memory': '128m', 'cpus': '0.50', 'pids_limit': 64, 'health': ['CMD', 'true'],
                'health_retries': 3}
        base.update(service)
        return {'schema_version': 1, 'catalog_id': 'probe', 'revision': 'abcdef1',
                'apps': [{'id': 'demo', 'name': 'demo', 'description': 'd', 'revoked': False,
                          'high_privilege': False, 'domain': False, 'bytes': 1024, 'nas_path': False,
                          'services': [base]}]}

    def parse(self, **service):
        return catalog.parse(json.dumps(self.document(**service)))

    def test_depends_on_within_application_only(self):
        two = self.document()
        second = json.loads(json.dumps(two['apps'][0]['services'][0]))
        second['id'] = 'web'
        second['depends_on'] = ['app']
        two['apps'][0]['services'].append(second)
        parsed = catalog.parse(json.dumps(two))
        self.assertEqual(parsed['apps']['demo']['services'][1]['depends_on'], ['app'])
        for bad, label in ((['missing'], 'undeclared'), (['web'], 'self'), (['app', 'app'], 'duplicate')):
            broken = self.document()
            broken['apps'][0]['services'][0]['id'] = 'web'
            broken['apps'][0]['services'][0]['depends_on'] = bad
            with self.assertRaises(ValueError, msg=label):
                catalog.parse(json.dumps(broken))
        cyclic = self.document()
        second = json.loads(json.dumps(cyclic['apps'][0]['services'][0]))
        second['id'] = 'web'
        second['depends_on'] = ['app']
        cyclic['apps'][0]['services'][0]['depends_on'] = ['web']
        cyclic['apps'][0]['services'].append(second)
        with self.assertRaises(ValueError):
            catalog.parse(json.dumps(cyclic))

    def test_sysctls_are_allowlisted_from_real_probe(self):
        # The allowlist is not aspirational: it is what Docker accepts without
        # --privileged on the verified host. vm.max_map_count is refused there.
        self.parse(sysctls={'net.core.somaxconn': '1024'})
        self.assertIn('net.core.somaxconn', catalog.SYSCTLS)
        self.assertNotIn('vm.max_map_count', catalog.SYSCTLS)
        for bad in ({'vm.max_map_count': '262144'}, {'fs.file-max': '1'}, {'net.core.somaxconn': '1\n2'}):
            with self.assertRaises(ValueError):
                self.parse(sysctls=bad)

    def test_shm_tmpfs_read_only_and_entrypoint(self):
        self.parse(shm_size='64m', tmpfs=['/run/probe'], read_only=True, entrypoint=['/bin/sh', '-c', 'sleep 1'])
        for bad in ({'shm_size': '64'}, {'shm_size': 64}):
            with self.assertRaises(ValueError):
                self.parse(**bad)
        for bad in ({'tmpfs': ['run/probe']}, {'tmpfs': ['/run/../etc']}, {'tmpfs': []}):
            with self.assertRaises(ValueError):
                self.parse(**bad)
        with self.assertRaises(ValueError):
            self.parse(read_only='yes')
        for bad in ({'entrypoint': []}, {'entrypoint': [1]}, {'entrypoint': ['']}):
            with self.assertRaises(ValueError):
                self.parse(**bad)

    def test_shell_entrypoint_with_argument_list_rejected(self):
        # Found by real deployment: "sh -c" + ["sleep","600"] actually runs `sleep`
        # with $0=600, so the container exits with a usage error at runtime.
        with self.assertRaises(ValueError):
            self.parse(entrypoint=['/bin/sh', '-c'], command=['sleep', '600'])
        with self.assertRaises(ValueError):
            self.parse(entrypoint=['/bin/sh', '-lc'], command=['a', 'b'])
        self.parse(entrypoint=['/bin/sh', '-c'], command=['true'])
        self.parse(entrypoint=['/bin/sh', '-c', 'sleep 600'])
        self.parse(entrypoint=['/usr/bin/nginx'], command=['-g', 'daemon off;'])

    def test_builtin_catalog_umami_is_consistent(self):
        apps = json.loads(catalog.BUILTIN.read_bytes())['apps']
        umami = next(app for app in apps if app['id'] == 'umami')
        services = {service['id']: service for service in umami['services']}
        self.assertEqual(services['app']['depends_on'], ['db'])
        self.assertTrue(services['app']['ports'] and services['db']['ports'] == [])
        self.assertEqual(services['db']['shm_size'], '64m')
        published = [port['published'] for service in umami['services'] for port in service['ports']]
        for other in apps:
            if other['id'] == 'umami':
                continue
            used = {port['published'] for service in other['services'] for port in service['ports']}
            self.assertFalse(used.intersection(published))


if __name__ == '__main__':
    unittest.main()
