"""SSH preflight is observational, never permission to activate a candidate."""
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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src/lib'))
import system_safety as safety


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'sshd_config'
        self.path.write_text('Port 5522\n')
        self.commands = []

    def command(self, *args):
        self.commands.append(args)
        if args[:2] == ('sshd', '-t'):
            return 0, ''
        if args[:2] == ('sshd', '-T'):
            return 0, 'port 5522\npermitrootlogin yes\npasswordauthentication yes\nhostkey /private/key\n'
        if args[0] == 'systemctl':
            return (0, 'active\n') if args[-1].endswith('.service') else (3, 'inactive\n')
        if args[0] == 'ss':
            return 0, 'LISTEN 0 128 0.0.0.0:5522 0.0.0.0:*\n'
        raise AssertionError('Unexpected command')

    def inspect(self, callback=None):
        with patch.object(safety, 'regular'), patch.object(safety.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(safety, '_command_output', side_effect=callback or self.command), contextlib.redirect_stdout(io.StringIO()):
            return safety.ssh_preflight(self.path)

    def test_valid_config_is_not_switch_approval(self):
        result = self.inspect()
        self.assertFalse(result['switch_allowed'])
        self.assertTrue(result['switch_blockers'])
        self.assertFalse(result['mutation_performed'])
        self.assertEqual(result['effective']['port'], ['5522'])
        self.assertNotIn('hostkey', result['effective'])
        self.assertEqual(result['listeners'], ['0.0.0.0:5522'])
        self.assertEqual(self.path.read_text(), 'Port 5522\n')
        self.assertFalse(any('reload' in cmd or 'restart' in cmd for cmd in self.commands))

    def test_bus_failure_is_unknown_not_inactive(self):
        def command(*args):
            return (1, '') if args[0] == 'systemctl' else self.command(*args)
        result = self.inspect(command)
        self.assertTrue(all(value is None for value in result['service'].values()))
        self.assertFalse(result['service_state_complete'])
        self.assertFalse(result['switch_allowed'])

    def test_active_socket_is_reported(self):
        def command(*args):
            return (0, 'active\n') if args[0] == 'systemctl' else self.command(*args)
        self.assertTrue(self.inspect(command)['socket_activation_detected'])

    def test_config_failure_stops_inspection(self):
        def command(*args):
            self.assertEqual(args[:2], ('sshd', '-t'))
            return 1, ''
        with self.assertRaisesRegex(ValueError, 'validation failed'):
            self.inspect(command)

    def test_effective_failure_is_not_success(self):
        def command(*args):
            return (1, '') if args[:2] == ('sshd', '-T') else self.command(*args)
        with self.assertRaisesRegex(ValueError, 'effective'):
            self.inspect(command)

    def test_listener_failure_is_unknown(self):
        def command(*args):
            return (None, None) if args[0] == 'ss' else self.command(*args)
        self.assertIsNone(self.inspect(command)['listeners'])

    @unittest.skipUnless(os.name == 'posix' and os.geteuid() == 0, 'Linux root CLI fixture')
    def test_cli_no_startup_files_or_telemetry(self):
        home = Path(self.temp.name) / 'home'
        home.mkdir()
        config = home / '.config/fusionbox'
        config.mkdir(parents=True)
        (config / 'config.yaml').write_text('general:\n  stats: true\n')
        before = {p.relative_to(home).as_posix(): p.read_bytes() for p in home.rglob('*') if p.is_file()}
        env = dict(os.environ, HOME=str(home), PYTHONDONTWRITEBYTECODE='1')
        result = subprocess.run(['bash', str(ROOT / 'fusion.sh'), 'system', 'ssh-preflight'],
                                env=env, capture_output=True, text=True, timeout=55)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertFalse(json.loads(result.stdout)['switch_allowed'])
        after = {p.relative_to(home).as_posix(): p.read_bytes() for p in home.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        for args in [('cluster', 'oracle', 'detect'), ('cl', 'oc', 'help'), ('cluster', 'oracle', 'status')]:
            result = subprocess.run(['bash', str(ROOT / 'fusion.sh'), *args],
                                    env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        after = {p.relative_to(home).as_posix(): p.read_bytes() for p in home.rglob('*') if p.is_file()}
        self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
