"""Managed catalog safety tests; Docker calls isolated from host resources."""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_apps as m
import market_catalog


@unittest.skipIf(os.name == 'nt', 'Linux flock lifecycle')
class Market(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.addCleanup(patch.stopall)
        patch.object(m.cb, 'BASE', self.base).start()
        self.docker = patch.object(m.cb, 'docker', return_value=b'').start()
        self.preflight = patch.object(m, 'preflight').start()
        patch.object(m, 'pull', return_value='sha256:' + 'a' * 64).start()
        patch.object(m.cb, 'inspect').start()
        self.up = patch.object(m, 'up').start()
        self.registry = self.base / 'fb-market-nginx.json'

    def install(self):
        m.operate('install', accepted=True)
        return m.load(self.registry, 'fb-market-nginx')

    def test_install_private_registry_and_localhost(self):
        r = self.install()
        self.assertEqual(self.registry.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.base.stat().st_mode & 0o777, 0o700)
        self.assertEqual(m.document(r)['services']['app']['ports'], ['127.0.0.1:8080:80'])
        self.assertTrue(m.document(r)['services']['app']['volumes'][0].endswith(':ro'))
        with self.assertRaises(ValueError): self.install()

    def test_confirmation_and_unknown_type(self):
        for action in ('install', 'update', 'uninstall'):
            with self.assertRaises(ValueError): m.operate(action)
        with self.assertRaises(ValueError): m.operate('install', app='other', accepted=True)
        with self.assertRaises(ValueError): m.operate('uninstall', accepted=True)
        self.docker.assert_not_called()

    def test_partial_install_retained_not_success(self):
        self.up.side_effect = RuntimeError('partial create/health failure')
        with self.assertRaisesRegex(RuntimeError, 'Install failed'): self.install()
        r = m.load(self.registry, 'fb-market-nginx')
        self.assertEqual(r['market']['state'], 'install-failed')
        self.assertTrue(Path(r['compose']).exists())
        self.assertFalse(any(c.args[0] in ('rm', 'stop') for c in self.docker.call_args_list))

    def test_unknown_docker_resource_never_adopted(self):
        self.docker.return_value = b'unknown'
        with self.assertRaisesRegex(ValueError, 'unmanaged'): self.install()
        self.assertFalse(self.registry.exists())

    def test_changed_config_and_registry_rejected(self):
        r = self.install()
        Path(r['compose']).write_text('{}')
        with self.assertRaises(ValueError): m.operate('uninstall', accepted=True)
        m.write_compose(r)
        r['market']['owner'] = 'unknown'; m.save(self.registry, r)
        with self.assertRaises(ValueError): m.operate('update', accepted=True)

    def test_lock_conflict(self):
        with m.cb.lock('another'):
            with self.assertRaisesRegex(ValueError, 'active'): self.install()
        self.docker.assert_not_called()

    def test_uninstall_preserves_data_and_metadata(self):
        r = self.install()
        c = {'Id': 'owned'}
        with patch.object(m, 'resources', return_value=[c]):
            m.operate('uninstall', accepted=True)
        self.assertEqual(self.docker.call_args_list[-2].args, ('stop', 'owned'))
        self.assertEqual(self.docker.call_args_list[-1].args, ('rm', 'owned'))
        self.assertTrue(Path(r['compose']).exists())
        self.assertEqual(json.loads(self.registry.read_text())['market']['state'], 'uninstalled')

    def test_uninstall_stop_failure_never_reports_success(self):
        self.install()
        with patch.object(m, 'resources', return_value=[{'Id': 'owned'}]):
            self.docker.side_effect = RuntimeError('stop failed')
            with self.assertRaises(RuntimeError): m.operate('uninstall', accepted=True)
        self.assertEqual(json.loads(self.registry.read_text())['market']['state'], 'healthy')

    def test_update_failed_health_rolls_back_exact_image(self):
        r = self.install()
        self.up.side_effect = [RuntimeError('health'), None]
        with patch.object(m, 'resources', return_value=[]), patch.object(m, 'health', return_value='healthy'), patch.object(m, 'pull', return_value='sha256:' + 'b' * 64):
            with self.assertRaisesRegex(RuntimeError, 'previous image restored'):
                m.operate('update', accepted=True)
        actual = m.load(self.registry, 'fb-market-nginx')
        self.assertEqual(actual['market']['image'], r['market']['image'])
        self.assertEqual(actual['market']['state'], 'healthy')
        self.assertTrue((self.base / 'fb-market-nginx.previous.json').exists())

    def test_double_update_failure_retains_recovery(self):
        self.install()
        self.up.side_effect = RuntimeError('health')
        with patch.object(m, 'resources', return_value=[]), patch.object(m, 'health', return_value='healthy'), patch.object(m, 'pull', return_value='sha256:' + 'b' * 64):
            with self.assertRaisesRegex(RuntimeError, 'AND rollback failed'):
                m.operate('update', accepted=True)
        self.assertEqual(m.load(self.registry, 'fb-market-nginx')['market']['state'], 'recovery-required')

    def test_unknown_volume_ownership(self):
        r = self.install()
        self.docker.side_effect = [b'', b'', b'fb-market-nginx_data']
        with patch.object(m.cb, 'js', return_value=[{'Labels': {}, 'Driver': 'local'}]):
            with self.assertRaisesRegex(ValueError, 'volume ownership'): m.resources(r)

    def test_reinstall_reuses_image_and_data(self):
        r = self.install()
        r['market']['state'] = 'uninstalled'; m.save(self.registry, r)
        with patch.object(m, 'resources', return_value=[]), patch.object(m.cb, 'js', return_value=[{'Id': r['market']['image']}]), patch.object(m.cb, 'docker', return_value=b'fb-market-nginx_data'):
            m.operate('reinstall', accepted=True, reuse=True)
        self.assertEqual(m.load(self.registry, r['project'])['market']['state'], 'healthy')

    def test_reinstall_failure_preserves_original_and_cleans_only_new_container(self):
        r = self.install()
        r['market']['state'] = 'uninstalled'; m.save(self.registry, r)
        before = self.registry.read_bytes(), Path(r['compose']).read_bytes()
        self.up.side_effect = RuntimeError('port collision')
        with patch.object(m, 'resources', side_effect=[[], [{'Id': 'new-owned'}]]), patch.object(m.cb, 'js', return_value=[{'Id': r['market']['image']}]), patch.object(m.cb, 'docker', return_value=b'fb-market-nginx_data') as docker:
            with self.assertRaisesRegex(RuntimeError, 'original registry/config/data retained'):
                m.operate('reinstall', accepted=True, reuse=True, port=8081)
        self.assertEqual(before, (self.registry.read_bytes(), Path(r['compose']).read_bytes()))
        self.assertEqual(docker.call_args_list[-2].args, ('stop', 'new-owned'))
        self.assertEqual(docker.call_args_list[-1].args, ('rm', 'new-owned'))

    def test_reinstall_missing_data_image_or_confirmation_refused(self):
        r = self.install()
        r['market']['state'] = 'uninstalled'; m.save(self.registry, r)
        before = self.registry.read_bytes(), Path(r['compose']).read_bytes()
        with self.assertRaisesRegex(ValueError, 'reuse-data'): m.operate('reinstall', accepted=True)
        with patch.object(m, 'resources', return_value=[]):
            with self.assertRaisesRegex(ValueError, 'volume missing'): m.operate('reinstall', accepted=True, reuse=True)
            with patch.object(m.cb, 'docker', return_value=b'fb-market-nginx_data'), patch.object(m.cb, 'js', side_effect=RuntimeError('image absent')):
                with self.assertRaises(RuntimeError): m.operate('reinstall', accepted=True, reuse=True)
        self.assertEqual(before, (self.registry.read_bytes(), Path(r['compose']).read_bytes()))

    def test_reinstall_conflict_and_cleanup_failure_preserve_recovery(self):
        r = self.install()
        r['market']['state'] = 'uninstalled'; m.save(self.registry, r)
        before = self.registry.read_bytes(), Path(r['compose']).read_bytes()
        with patch.object(m, 'resources', return_value=[{'Id': 'existing'}]):
            with self.assertRaisesRegex(ValueError, 'no existing'): m.operate('reinstall', accepted=True, reuse=True)
        self.up.side_effect = RuntimeError('health')
        with patch.object(m, 'resources', side_effect=[[], ValueError('unknown intruder')]), patch.object(m.cb, 'js', return_value=[{'Id': r['market']['image']}]), patch.object(m.cb, 'docker', return_value=b'fb-market-nginx_data') as docker:
            with self.assertRaisesRegex(RuntimeError, 'cleanup failed'): m.operate('reinstall', accepted=True, reuse=True, port=8081)
            self.assertFalse(any(c.args[0] in ('stop', 'rm') for c in docker.call_args_list))
        self.assertEqual(before, (self.registry.read_bytes(), Path(r['compose']).read_bytes()))

    def test_new_catalog_entries_validate(self):
        for app, target, min_bytes in (('uptime-kuma', 3001, 1024 * 1024 * 1024),
                                       ('ddns-go', 9876, 256 * 1024 * 1024),
                                       ('new-api', 3000, 512 * 1024 * 1024),
                                       ('lobe-chat', 3210, 512 * 1024 * 1024),
                                       ('open-webui', 8080, 4 * 1024 * 1024 * 1024),
                                       ('n8n', 5678, 512 * 1024 * 1024),
                                       ('openlist', 5244, 512 * 1024 * 1024),
                                       ('navidrome', 4533, 512 * 1024 * 1024)):
            spec = m.metadata(app)
            self.assertEqual(spec['target'], target)
            self.assertGreaterEqual(spec['bytes'], min_bytes)
            self.assertIn('@sha256:', spec['image'])
            self.assertFalse(spec['domain'])
            doc = m.document({'project': 'fb-market-' + app.replace('-', ''),
                              'market': {'token': 'a' * 32, 'app': app, 'port': 12345,
                                         'image': spec['image']},
                              'compose': 'x'})
            self.assertIn('127.0.0.1:12345:' + str(target), doc['services']['app']['ports'])

    def test_multi_volume_document(self):
        spec = m.metadata('navidrome')
        doc = m.document({'project': 'fb-market-navidrome',
                          'market': {'token': 'a' * 32, 'app': 'navidrome', 'port': 12345,
                                     'image': spec['image']},
                          'compose': 'x'})
        service = doc['services']['app']
        self.assertIn('data:/data', service['volumes'])
        self.assertIn('music:/music:ro', service['volumes'])
        self.assertEqual(doc['volumes']['music']['name'], 'fb-market-navidrome_music')

    def test_environment_passthrough(self):
        spec = m.metadata('n8n')
        doc = m.document({'project': 'fb-market-n8n',
                          'market': {'token': 'a' * 32, 'app': 'n8n', 'port': 12345,
                                     'image': spec['image']},
                          'compose': 'x'})
        self.assertEqual(doc['services']['app']['environment']['N8N_SECURE_COOKIE'], 'false')

    def test_ntfy_metadata_runtime_and_identity(self):
        m.operate('install', app='ntfy', accepted=True)
        registry = self.base / 'fb-market-ntfy.json'
        r = m.load(registry, 'fb-market-ntfy')
        service = m.document(r)['services']['app']
        self.assertEqual(service['user'], '65534:65534')
        self.assertEqual(service['ports'], ['127.0.0.1:8081:8080'])
        self.assertEqual(service['cap_drop'], ['ALL'])
        self.assertEqual(service['volumes'], ['data:/tmp'])
        with self.assertRaisesRegex(ValueError, 'identity mismatch'):
            m.operate('uninstall', app='nginx', project='fb-market-ntfy', accepted=True)

    def test_ntfy_changed_image_refused_before_mutation(self):
        m.operate('install', app='ntfy', accepted=True)
        registry = self.base / 'fb-market-ntfy.json'
        r = m.load(registry, 'fb-market-ntfy')
        before = registry.read_bytes(), Path(r['compose']).read_bytes()
        self.up.reset_mock()
        with patch.object(m, 'resources', return_value=[]), patch.object(m, 'health', return_value='healthy'), patch.object(m, 'pull', return_value='sha256:' + 'b' * 64):
            with self.assertRaisesRegex(ValueError, 'upgrade refused'):
                m.operate('update', app='ntfy', accepted=True)
        self.up.assert_not_called()
        self.assertEqual(before, (registry.read_bytes(), Path(r['compose']).read_bytes()))

    def test_ntfy_domain_and_invalid_action_rejected_before_docker(self):
        for action in ('domain', 'tls', 'tls-refresh', 'invalid'):
            with self.assertRaises(ValueError): m.operate(action, app='ntfy', accepted=True)
        self.docker.assert_not_called()

    def test_invalid_metadata_rejected_before_docker(self):
        for field, value in [('bytes', -1), ('port', 0), ('target', '80'), ('image', 'evil;command'), ('readonly', 'yes')]:
            with patch.dict(m.CATALOG['ntfy'], {field: value}):
                with self.assertRaisesRegex(ValueError, 'metadata'):
                    m.operate('install', app='ntfy', accepted=True)
        self.docker.assert_not_called()

    def test_ntfy_unknown_container_owner_rejected(self):
        m.operate('install', app='ntfy', accepted=True)
        r = m.load(self.base / 'fb-market-ntfy.json', 'fb-market-ntfy')
        self.docker.return_value = b'unknown'
        with patch.object(m.cb, 'js', return_value=[{'Config': {'Labels': {}}, 'HostConfig': {}}]):
            with self.assertRaisesRegex(ValueError, 'ownership'): m.resources(r)

    def test_unhealthy_update_blocked(self):
        self.install()
        with patch.object(m, 'resources', return_value=[]), patch.object(m, 'health', return_value='unhealthy'):
            with self.assertRaisesRegex(ValueError, 'healthy'): m.operate('update', accepted=True)


@unittest.skipIf(os.name == 'nt', 'Linux flock lifecycle')
class ManifestLifecycle(unittest.TestCase):
    """Declarative multi-container lifecycle: emission, drift checks and transactions."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.addCleanup(patch.stopall)
        patch.object(m.cb, 'BASE', self.base).start()
        patch.object(m.cb, 'no_links').start()
        self.docker = patch.object(m.cb, 'docker', return_value=b'').start()
        self.spec = {
            'id': 'stack', 'name': 'stack', 'description': 'd', 'revoked': False,
            'high_privilege': False, 'domain': False, 'bytes': 1024, 'nas_path': False,
            'services': [
                {'id': 'db', 'image': 'postgres@sha256:' + 'a' * 64, 'ports': [],
                 'volumes': [{'name': 'data', 'target': '/var/lib/postgresql/data', 'read_only': False}],
                 'binds': [], 'devices': [], 'network_mode': 'bridge', 'docker_socket': False,
                 'memory': '256m', 'cpus': '0.50', 'pids_limit': 128,
                 'health': ['CMD-SHELL', 'pg_isready'], 'health_retries': 30, 'shm_size': '64m'},
                {'id': 'app', 'image': 'ghcr.io/example/app@sha256:' + 'b' * 64,
                 'depends_on': ['db'], 'ports': [{'published': 8090, 'target': 3000, 'protocol': 'tcp'}],
                 'volumes': [], 'binds': [], 'devices': [], 'network_mode': 'bridge',
                 'docker_socket': False, 'memory': '1024m', 'cpus': '0.50', 'pids_limit': 256,
                 'health': ['CMD', 'true'], 'health_retries': 90}],
        }
        self.record = {'owner': m.cb.OWNER, 'project': 'fb-market-stack',
                       'compose': str(self.base / 'fb-market-stack.compose.json'),
                       'market': {'owner': m.OWNER, 'app': 'stack', 'token': 'c' * 32,
                                  'state': 'healthy', 'catalog_app': self.spec,
                                  'catalog_digest': market_catalog.app_digest(self.spec)}}
        self.registry = self.base / 'fb-market-stack.json'
        patch.object(m, 'catalog_apps', return_value={'stack': self.spec}).start()
        patch.object(m, 'docker_preflight').start()
        patch.object(m, 'health', return_value='healthy').start()
        self.up = patch.object(m, 'up').start()

    def test_document_emits_multi_container_fields(self):
        doc = m.document(self.record)['services']
        self.assertEqual(doc['app']['depends_on'], {'db': {'condition': 'service_healthy'}})
        self.assertEqual(doc['db']['shm_size'], '64m')
        self.assertEqual(doc['app']['ports'], ['127.0.0.1:8090:3000/tcp'])
        # Catalog `bridge` must not become the literal Docker default bridge, or the
        # services cannot resolve each other (found by real deployment).
        self.assertNotIn('network_mode', doc['app'])
        self.assertNotIn('network_mode', doc['db'])

    def test_host_network_passes_through(self):
        self.spec['services'][1]['network_mode'] = 'host'
        self.spec['services'][1]['ports'] = []
        self.record['market']['catalog_digest'] = market_catalog.app_digest(self.spec)
        self.assertEqual(m.document(self.record)['services']['app']['network_mode'], 'host')

    def test_structural_change_is_refused(self):
        for mutate in ('service set', 'volumes', 'ports'):
            live = json.loads(json.dumps(self.spec))
            if mutate == 'service set':
                live['services'][1]['id'] = 'worker'
            elif mutate == 'volumes':
                live['services'][0]['volumes'][0]['name'] = 'other'
            else:
                live['services'][1]['ports'][0]['published'] = 9999
            with patch.object(m, 'catalog_apps', return_value={'stack': live}):
                with self.assertRaises(ValueError, msg=mutate):
                    m.manifest_target(self.record)

    def test_image_override_rules(self):
        target = m.manifest_target(self.record)
        with self.assertRaises(ValueError):
            m.manifest_images(self.record, target, {'nope': 'nginx@sha256:' + 'd' * 64})
        with self.assertRaises(ValueError):
            m.manifest_images(self.record, target, {'app': 'nginx:latest'})
        changed = m.manifest_images(self.record, m.manifest_target(self.record), {'db': 'postgres@sha256:' + 'e' * 64})
        self.assertEqual(list(changed), ['db'])
        self.assertEqual(m.manifest_images(self.record, m.manifest_target(self.record), {}), {})

    def test_update_no_change_is_a_no_op(self):
        m.save(self.registry, self.record)
        m.write_compose(self.record)
        m.operate('update', 'stack', accepted=True)
        self.up.assert_not_called()
        self.assertFalse((self.base / 'fb-market-stack.update.json').exists())
        self.assertEqual(json.loads(self.registry.read_text())['market']['state'], 'healthy')

    def test_update_replaces_image_and_commits(self):
        patch.object(m, 'ensure_images').start()
        m.manifest_update(self.registry, self.record, {'app': 'ghcr.io/example/app@sha256:' + 'f' * 64})
        saved = json.loads(self.registry.read_text())
        self.assertEqual(saved['market']['state'], 'healthy')
        self.assertTrue(saved['market']['catalog_app']['services'][1]['image'].endswith('f' * 64))
        self.up.assert_called_once()
        self.assertFalse((self.base / 'fb-market-stack.update.json').exists())

    def test_update_failure_rolls_back_to_previous_image(self):
        patch.object(m, 'ensure_images').start()
        self.up.side_effect = [RuntimeError('unhealthy'), None]
        with self.assertRaises(RuntimeError):
            m.manifest_update(self.registry, self.record, {'app': 'ghcr.io/example/app@sha256:' + 'f' * 64})
        saved = json.loads(self.registry.read_text())
        self.assertEqual(saved['market']['state'], 'healthy')
        self.assertTrue(saved['market']['catalog_app']['services'][1]['image'].endswith('b' * 64))
        self.assertFalse((self.base / 'fb-market-stack.update.json').exists())

    def test_double_failure_retains_recovery_journal(self):
        patch.object(m, 'ensure_images').start()
        self.up.side_effect = RuntimeError('unhealthy')
        with self.assertRaises(RuntimeError):
            m.manifest_update(self.registry, self.record, {'app': 'ghcr.io/example/app@sha256:' + 'f' * 64})
        saved = json.loads(self.registry.read_text())
        self.assertEqual(saved['market']['state'], 'recovery-required')
        self.assertTrue((self.base / 'fb-market-stack.update.json').exists())

    def test_reinstall_requires_uninstalled_state_and_retained_volume(self):
        with self.assertRaises(ValueError):
            m.manifest_reinstall(self.registry, self.record)
        uninstalled = json.loads(json.dumps(self.record))
        uninstalled['market']['state'] = 'uninstalled'
        patch.object(m, 'resources', return_value=[]).start()
        with patch.object(m.cb, 'docker', return_value=b'other_data\n'):
            with self.assertRaises(ValueError):
                m.manifest_reinstall(self.registry, uninstalled)
        with patch.object(m.cb, 'docker', return_value=b'fb-market-stack_data\n'), patch.object(m, 'ensure_images'):
            m.manifest_reinstall(self.registry, uninstalled)
        self.assertEqual(json.loads(self.registry.read_text())['market']['state'], 'healthy')

    def test_resource_drift_is_detected(self):
        container = {
            'Id': 'x' * 64, 'Name': '/fb-market-stack-app',
            'Config': {'Labels': {'io.fusionbox.market': 'c' * 32, 'com.docker.compose.service': 'app',
                                  'com.docker.compose.project.config_files': self.record['compose']}},
            'HostConfig': {'NetworkMode': 'fb-market-stack_default', 'Privileged': False,
                           'ShmSize': 67108864, 'ReadonlyRootfs': False,
                           'Sysctls': None, 'Tmpfs': None},
            'Mounts': [], 'State': {'Running': True, 'Health': {'Status': 'healthy'}},
        }
        db = json.loads(json.dumps(container))
        db['Name'] = '/fb-market-stack-db'
        db['Config']['Labels']['com.docker.compose.service'] = 'db'
        db['HostConfig']['ShmSize'] = 64 * 1024 * 1024
        db['Mounts'] = [{'Type': 'volume', 'Name': 'fb-market-stack_data',
                         'Destination': '/var/lib/postgresql/data', 'RW': True}]
        volume = {'Labels': {'io.fusionbox.market': 'c' * 32, 'com.docker.compose.project': 'fb-market-stack'},
                  'Driver': 'local', 'Options': None}

        def fake_docker(*args):
            return b'fb-market-stack_data\n' if args[:2] == ('volume', 'ls') else b'x' * 64

        def fake_js(*args):
            return [volume] if args[0] == 'volume' else [container, db]

        docker = patch.object(m.cb, 'docker', side_effect=fake_docker).start()
        patch.object(m.cb, 'js', side_effect=fake_js).start()
        m.resources(self.record)
        # Any single declared capability drifting must be rejected, not silently accepted.
        for key, value, restore in (('ShmSize', 1, 64 * 1024 * 1024), ('ReadonlyRootfs', True, False)):
            db['HostConfig'][key] = value
            with self.assertRaises(ValueError, msg=key):
                m.resources(self.record)
            db['HostConfig'][key] = restore
        for key, value in (('Sysctls', {'net.core.somaxconn': '1024'}), ('Tmpfs', {'/run/probe': ''})):
            db['HostConfig'][key] = value
            with self.assertRaises(ValueError, msg=key):
                m.resources(self.record)
            db['HostConfig'][key] = None
        container['Config']['Entrypoint'] = ['/bin/sh', '-c']
        self.spec['services'][1]['entrypoint'] = ['/usr/bin/entry']
        self.record['market']['catalog_digest'] = market_catalog.app_digest(self.spec)
        with self.assertRaises(ValueError):
            m.resources(self.record)
        container['HostConfig']['NetworkMode'] = 'bridge'
        with self.assertRaises(ValueError):
            m.resources(self.record)
        docker.assert_called()


class Preflight(unittest.TestCase):
    def test_auto_port_bounded_and_errors_not_hidden(self):
        import errno
        with patch.object(m, 'preflight', side_effect=[OSError(errno.EADDRINUSE, 'occupied'), None]) as probe:
            self.assertEqual(m.select_port(8080, True), 8081)
            self.assertEqual([c.args[0] for c in probe.call_args_list], [8080, 8081])
        with patch.object(m, 'preflight', side_effect=ValueError('Port already published by Docker')) as probe:
            with self.assertRaisesRegex(ValueError, '20-port'): m.select_port(8080, True)
            self.assertEqual(probe.call_count, 20)
        with patch.object(m, 'preflight', side_effect=ValueError('disk full')) as probe:
            with self.assertRaisesRegex(ValueError, 'disk full'): m.select_port(8080, True)
            self.assertEqual(probe.call_count, 1)

    def test_port_occupied(self):
        with socket.socket() as listener, tempfile.TemporaryDirectory() as root:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            with patch.object(m.cb, 'BASE', Path(root)), patch.object(m.cb, 'docker'), patch.object(m.cb, 'js', return_value=root):
                with self.assertRaises(OSError): m.preflight(listener.getsockname()[1])

    def test_insufficient_disk_and_invalid_port(self):
        with patch.object(m.cb, 'docker'), patch.object(m.cb, 'js', return_value='/'), patch.object(m.shutil, 'disk_usage') as disk:
            disk.return_value.free = 0
            with self.assertRaisesRegex(ValueError, 'disk'): m.preflight(8080)
            with self.assertRaisesRegex(ValueError, 'Port'): m.preflight(0)

    def test_ntfy_disk_threshold(self):
        with patch.object(m.cb, 'docker'), patch.object(m.cb, 'js', return_value='/'), patch.object(m.shutil, 'disk_usage') as disk:
            disk.return_value.free = 300 * 1024 * 1024
            m.preflight(8080, False)
            with self.assertRaisesRegex(ValueError, '512 MiB'): m.preflight(8081, False, 'ntfy')

    def test_ntfy_health_requires_true_json(self):
        r = {'market': {'app': 'ntfy', 'port': 8081}}
        with patch.object(m, 'resources', return_value=[{'State': {'Running': True, 'Health': {'Status': 'healthy'}}}]), patch.object(m.urllib.request, 'build_opener') as opener:
            response = opener.return_value.open.return_value.__enter__.return_value
            response.status = 200
            for body in (b'{}', b'{"healthy":false}', b'not JSON', b'{"healthy":"true"}'):
                response.read.return_value = body
                self.assertEqual(m.health(r), 'unhealthy')
            response.read.return_value = b'{"healthy":true}'
            self.assertEqual(m.health(r), 'healthy')

    def test_health_failure_after_compose_success(self):
        with patch.object(m.cb, 'docker'), patch.object(m, 'health', return_value='unhealthy'):
            with self.assertRaisesRegex(RuntimeError, 'health'):
                m.up({'project': 'fixture', 'compose': '/private/compose'})


if __name__ == '__main__':
    unittest.main()
