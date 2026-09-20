"""Fail2Ban panel transactions; fail2ban-client/systemctl are mocked."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from test_safety import Safety, ROOT

spec = importlib.util.spec_from_file_location('system_safety', ROOT / 'src/lib/system_safety.py')
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


@unittest.skipIf(os.name == 'nt', 'POSIX ownership checks run on isolated Linux')
class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fusionbox-f2b-')
        self.root = Path(self.tmp.name)
        self.commands = []

    def tearDown(self):
        self.tmp.cleanup()

    def record(self, *args):
        self.commands.append(args)
        return ''

    def test_unban_validates_ip_before_calling_client(self):
        for bad in ('999.1.1.1', 'not-an-ip', '1.2.3.4 -o ProxyCommand=x', '', '1.2.3.4/32 extra'):
            with patch.object(safety, 'run', self.record):
                with self.assertRaises(ValueError):
                    safety.f2b_unban(bad)
        self.assertFalse(self.commands)

    def test_unban_accepts_ipv4_and_ipv6(self):
        for ip in ('192.0.2.7', '2001:db8::1'):
            with patch.object(safety, 'run', self.record):
                safety.f2b_unban(ip)
        self.assertIn(('fail2ban-client', 'set', 'sshd', 'unbanip', '192.0.2.7'), self.commands)
        self.assertIn(('fail2ban-client', 'set', 'sshd', 'unbanip', '2001:db8::1'), self.commands)

    def test_unban_client_failure_raises_with_reason(self):
        def fail(*args):
            self.commands.append(args)
            raise subprocess.CalledProcessError(1, args)
        with patch.object(safety, 'run', fail):
            with self.assertRaises(ValueError):
                safety.f2b_unban('192.0.2.7')

    def test_uninstall_removes_only_owned_marker_file(self):
        directory = self.root / 'fail2ban'
        (directory / 'jail.d').mkdir(parents=True)
        owned = directory / 'jail.d/99-fusionbox-sshd.local'
        owned.write_text('# FusionBox managed sshd parameters v1\n[sshd]\nmaxretry = 5\n')
        foreign = directory / 'jail.local'
        foreign.write_text('[sshd]\nenabled = true\n')

        def systemctl(args, check=False, **kw):
            self.commands.append(tuple(args))
            return subprocess.CompletedProcess(args, 0, '', '')

        with patch.object(safety.subprocess, 'run', systemctl):
            safety.f2b_uninstall(directory)
        self.assertIn(('systemctl', 'disable', '--now', 'fail2ban'), self.commands)
        self.assertFalse(owned.exists())
        self.assertTrue(foreign.exists())

    def test_uninstall_without_owned_file_still_disables(self):
        directory = self.root / 'fail2ban'
        directory.mkdir()

        def systemctl(args, check=False, **kw):
            self.commands.append(tuple(args))
            return subprocess.CompletedProcess(args, 0, '', '')

        with patch.object(safety.subprocess, 'run', systemctl):
            safety.f2b_uninstall(directory)
        self.assertIn(('systemctl', 'disable', '--now', 'fail2ban'), self.commands)

    def test_uninstall_refuses_foreign_jail_file(self):
        directory = self.root / 'fail2ban'
        (directory / 'jail.d').mkdir(parents=True)
        target = directory / 'jail.d/99-fusionbox-sshd.local'
        target.write_text('[sshd]\nmaxretry = 1\n')

        def systemctl(args, check=False, **kw):
            self.commands.append(tuple(args))
            return subprocess.CompletedProcess(args, 0, '', '')

        with patch.object(safety.subprocess, 'run', systemctl):
            with self.assertRaises(ValueError):
                safety.f2b_uninstall(directory)
        self.assertTrue(target.exists())
        self.assertNotIn(('systemctl', 'disable', '--now', 'fail2ban'), self.commands)


class Fail2BanMenus(Safety):
    def test_unban_routes_to_safety_helper(self):
        body = '''python3() { printf '%s\\n' "$*" >> "$T/invoked"; }
system_fail2ban unban 192.0.2.7 || exit 9'''
        self.run_shell('system', body)
        self.assertIn('f2b-unban 192.0.2.7', (self.root / 'invoked').read_text())

    def test_unban_without_ip_refused_before_helper(self):
        body = '''python3() { printf '%s\\n' "$*" > "$T/invoked"; }
system_fail2ban unban || exit 9'''
        self.run_shell('system', body, 9)
        self.assertFalse((self.root / 'invoked').exists())

    def test_banned_parses_client_output(self):
        body = '''fail2ban-client() { case "$*" in *"status sshd"*) printf 'Status for the jail: sshd\\n|- Currently banned: 1\\n`- Banned IP list:\\t192.0.2.7 198.51.100.9\\n';; *) printf 'Jail list:\\tsshd\\n';; esac; }
msg() { printf '%s\\n' "$*" >> "$T/out"; }
system_fail2ban banned || exit 9'''
        self.run_shell('system', body)
        self.assertIn('192.0.2.7 198.51.100.9', (self.root / 'out').read_text())

    def test_banned_empty_reports_none(self):
        body = '''fail2ban-client() { printf 'Status for the jail: sshd\\n`- Banned IP list:\\t\\n'; }
msg() { printf '%s\\n' "$*" >> "$T/out"; }
system_fail2ban banned || exit 9'''
        self.run_shell('system', body)
        self.assertIn('无封禁', (self.root / 'out').read_text())

    def test_log_tails_bounded_lines(self):
        logfile = self.root / 'var/log/fail2ban.log'
        logfile.parent.mkdir(parents=True, exist_ok=True)
        logfile.write_text(''.join(f'line{i}\n' for i in range(1, 21)))
        out = self.run_shell('system', 'system_fail2ban log 5')
        self.assertNotIn('line15', out)
        self.assertIn('line20', out)

    def test_log_rejects_non_numeric(self):
        body = '''system_fail2ban log '5; rm -rf /tmp' || exit 9'''
        self.run_shell('system', body, 9)

    def test_params_routes_numbers_only(self):
        body = '''python3() { printf '%s\\n' "$*" >> "$T/invoked"; }
system_fail2ban params 5 600 || exit 9'''
        self.run_shell('system', body)
        self.assertIn('fail2ban 5 600', (self.root / 'invoked').read_text())

    def test_params_rejects_non_numeric_before_helper(self):
        body = '''python3() { printf '%s\\n' "$*" > "$T/invoked"; }
system_fail2ban params five 600 || exit 9'''
        self.run_shell('system', body, 9)
        self.assertFalse((self.root / 'invoked').exists())

    def test_uninstall_full_path_calls_helper_then_package_manager(self):
        body = '''python3() { printf '%s\\n' "$*" >> "$T/invoked"; }
command() { if [[ "$1" == "-v" && "$2" == "fail2ban-client" && -n "${APT_RAN:-}" ]]; then return 1; fi; builtin command "$@"; }
fail2ban-client() { return 0; }
apt-get() { printf 'apt-get %s\\n' "$*" >> "$T/invoked"; APT_RAN=1; return 0; }
F_PKG_MGR=apt
system_fail2ban uninstall || exit 9'''
        self.run_shell('system', body)
        invoked = (self.root / 'invoked').read_text()
        self.assertIn('f2b-uninstall', invoked)
        self.assertIn('apt-get purge -y fail2ban', invoked)

    def test_status_requires_client(self):
        body = '''msg_err() { printf '%s\\n' "$*" >> "$T/out"; }
mkdir -p "$T/nobin"
PATH="$T/nobin"
_f2b_status; echo "rc=$?" >> "$T/out"'''
        self.run_shell('system', body)
        content = (self.root / 'out').read_text()
        self.assertIn('未安装 Fail2Ban', content)
        self.assertIn('rc=1', content)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Transactions)
    suite.addTests(Fail2BanMenus(name) for name in Fail2BanMenus.__dict__ if name.startswith('test_'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
