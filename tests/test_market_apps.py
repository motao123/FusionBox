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

    def test_unhealthy_update_blocked(self):
        self.install()
        with patch.object(m, 'resources', return_value=[]), patch.object(m, 'health', return_value='unhealthy'):
            with self.assertRaisesRegex(ValueError, 'healthy'): m.operate('update', accepted=True)


class Preflight(unittest.TestCase):
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

    def test_health_failure_after_compose_success(self):
        with patch.object(m.cb, 'docker'), patch.object(m, 'health', return_value='unhealthy'):
            with self.assertRaisesRegex(RuntimeError, 'health'):
                m.up({'project': 'fixture', 'compose': '/private/compose'})


if __name__ == '__main__':
    unittest.main()
