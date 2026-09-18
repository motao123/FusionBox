"""User administration transactions; account commands are mocked, files are real."""
import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from test_safety import Safety, ROOT

spec = importlib.util.spec_from_file_location('system_safety', ROOT / 'src/lib/system_safety.py')
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


class FakeEntry:
    def __init__(self, uid, gid, home):
        self.pw_uid = uid
        self.pw_gid = gid
        self.pw_dir = str(home)


@unittest.skipIf(os.name == 'nt', 'POSIX account and ownership checks run on isolated Linux')
class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fusionbox-users-')
        self.root = Path(self.tmp.name)
        self.sudo_dir = self.root / 'etc/sudoers.d'
        self.sudo_dir.mkdir(parents=True)
        self.commands = []

    def tearDown(self):
        self.tmp.cleanup()

    def record(self, *args):
        self.commands.append(args)
        return ''

    def entry(self, home=None, uid=None):
        return FakeEntry(uid if uid is not None else os.geteuid(), os.getgid(),
                         home or self.root / 'home')

    def test_user_add_creates_with_home_and_shell(self):
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', side_effect=KeyError):
            safety.user_add('deploy1')
        self.assertIn(('useradd', '-m', '-s', '/bin/bash', 'deploy1'), self.commands)

    def test_user_add_refuses_existing_and_invalid_names(self):
        with patch.object(safety, 'run', self.record):
            with patch('pwd.getpwnam', return_value=self.entry()):
                with self.assertRaises(ValueError):
                    safety.user_add('deploy1')
            for bad in ('Deploy1', '1abc', 'a' * 33, '../root', 'a b', '', 'a:b'):
                with self.assertRaises(ValueError):
                    safety.user_add(bad)
        self.assertFalse(self.commands)

    def test_passwd_rejects_bad_input_and_unknown_user(self):
        with patch('pwd.getpwnam', side_effect=KeyError):
            with self.assertRaises(ValueError):
                safety.passwd_set('ghost', 'x')
        with patch('pwd.getpwnam', return_value=self.entry()):
            for bad in ('', 'a:b', 'a\nb', 'a\rb', 'x' * 513):
                with self.assertRaises(ValueError):
                    safety.passwd_set('deploy1', bad)
        self.assertFalse(self.commands)

    def test_passwd_sets_via_stdin_including_root(self):
        captured = {}

        def chpasswd(args, input=None, check=False, text=False, **kwargs):
            captured['args'] = args
            captured['input'] = input
            return subprocess.CompletedProcess(args, 0, '', '')

        for name, uid in (('deploy1', 1001), ('root', 0)):
            with patch('pwd.getpwnam', return_value=self.entry(self.root / ('home-' + name), uid)), \
                 patch.object(safety.subprocess, 'run', chpasswd):
                safety.passwd_set(name, 's3cret-' + name)
            self.assertEqual(captured['args'], ['chpasswd'])
            self.assertEqual(captured['input'], name + ':s3cret-' + name + '\n')

    def test_sudo_grant_installs_validated_0440(self):
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            safety.sudo_grant('deploy1', self.sudo_dir)
        target = self.sudo_dir / '90-fusionbox-deploy1'
        self.assertTrue(target.read_text().startswith(
            '# FusionBox managed sudo grant v1\ndeploy1 ALL=(ALL:ALL) ALL\n'))
        self.assertEqual(target.stat().st_mode & 0o777, 0o440)
        self.assertIn(('visudo', '-c', '-f', str(target)), self.commands)

    def test_sudo_grant_nopasswd_leaves_foreign_files(self):
        foreign = self.sudo_dir / '99-other'
        foreign.write_text('x ALL=(ALL) ALL\n')
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            safety.sudo_grant('deploy1', self.sudo_dir, nopasswd=True)
        self.assertIn('NOPASSWD:ALL', (self.sudo_dir / '90-fusionbox-deploy1').read_text())
        self.assertEqual(foreign.read_text(), 'x ALL=(ALL) ALL\n')

    def test_sudo_grant_refuses_unknown_file_without_touching_it(self):
        target = self.sudo_dir / '90-fusionbox-deploy1'
        target.write_text('deploy1 ALL=(ALL) ALL\n')
        target.chmod(0o440)
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            with self.assertRaises(ValueError):
                safety.sudo_grant('deploy1', self.sudo_dir)
        self.assertEqual(target.read_text(), 'deploy1 ALL=(ALL) ALL\n')
        self.assertFalse(self.commands)

    def test_sudo_grant_rolls_back_when_target_validation_fails(self):
        target = self.sudo_dir / '90-fusionbox-deploy1'

        def fail_target(*args):
            self.commands.append(args)
            if args[0] == 'visudo' and args[3].startswith(str(self.sudo_dir)):
                raise subprocess.CalledProcessError(1, args)
            return ''

        with patch.object(safety, 'run', fail_target), patch('pwd.getpwnam', return_value=self.entry()):
            with self.assertRaises(subprocess.CalledProcessError):
                safety.sudo_grant('deploy1', self.sudo_dir)
        self.assertFalse(target.exists())

    def test_sudo_revoke_only_removes_owned_marker_file(self):
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            with self.assertRaises(ValueError):
                safety.sudo_revoke('deploy1', self.sudo_dir)
        foreign = self.sudo_dir / '90-fusionbox-deploy1'
        foreign.write_text('deploy1 ALL=(ALL) ALL\n')
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            with self.assertRaises(ValueError):
                safety.sudo_revoke('deploy1', self.sudo_dir)
        self.assertTrue(foreign.exists())
        foreign.write_text('# FusionBox managed sudo grant v1\ndeploy1 ALL=(ALL:ALL) ALL\n')
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            safety.sudo_revoke('deploy1', self.sudo_dir)
        self.assertFalse(foreign.exists())

    def test_user_del_guards_uid_and_foreign_sudoers(self):
        managed = self.sudo_dir / '90-fusionbox-deploy1'
        managed.write_text('deploy1 ALL=(ALL:ALL) ALL\n')
        for uid in (0, 999):
            with patch.object(safety, 'run', self.record), \
                 patch('pwd.getpwnam', return_value=self.entry(uid=uid)):
                with self.assertRaises(ValueError):
                    safety.user_del('deploy1', self.sudo_dir)
        self.assertFalse(self.commands)
        foreign = self.sudo_dir / '90-fusionbox-deploy2'
        foreign.write_text('deploy2 ALL=(ALL) ALL\n')
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            with self.assertRaises(ValueError):
                safety.user_del('deploy2', self.sudo_dir)
        self.assertFalse(self.commands)
        with patch.object(safety, 'run', self.record), patch('pwd.getpwnam', return_value=self.entry()):
            safety.user_del('deploy1', self.sudo_dir)
        self.assertIn(('userdel', '-r', 'deploy1'), self.commands)
        self.assertFalse(managed.exists())
        self.assertTrue(foreign.exists())

    def test_user_key_install_sets_ownership_and_appends(self):
        key = self.root / 'genkey'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        public = key.with_suffix('.pub').read_text().strip()
        home = self.root / 'home/deploy1'
        home.mkdir(parents=True)
        with patch.object(safety, 'run', self.record), \
             patch('pwd.getpwnam', return_value=self.entry(home)):
            safety.user_key_install('deploy1', public)
        ssh_dir = home / '.ssh'
        authorized = ssh_dir / 'authorized_keys'
        self.assertEqual(ssh_dir.stat().st_mode & 0o777, 0o700)
        self.assertEqual(authorized.stat().st_mode & 0o777, 0o600)
        self.assertEqual(authorized.stat().st_uid, os.geteuid())
        self.assertIn(public, authorized.read_text())
        with patch.object(safety, 'run', self.record), \
             patch('pwd.getpwnam', return_value=self.entry(home)):
            safety.user_key_install('deploy1', public)
        self.assertEqual(len(authorized.read_text().strip().splitlines()), 2)

    def test_user_key_install_refuses_symlink_and_bad_key(self):
        key = self.root / 'genkey'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        public = key.with_suffix('.pub').read_text().strip()
        home = self.root / 'home/deploy1'
        home.mkdir(parents=True)
        (home / '.ssh').symlink_to(self.root)
        with patch.object(safety, 'run', self.record), \
             patch('pwd.getpwnam', return_value=self.entry(home)):
            with self.assertRaises(ValueError):
                safety.user_key_install('deploy1', public)
        (home / '.ssh').unlink()
        for bad in ('not a key', public + '\nsecond', ' ' + public):
            with patch.object(safety, 'run', self.record), \
                 patch('pwd.getpwnam', return_value=self.entry(home)):
                with self.assertRaises(ValueError):
                    safety.user_key_install('deploy1', bad)
        self.assertFalse((home / '.ssh' / 'authorized_keys').exists())

    def test_ssh_permitrootlogin_updates_and_reloads(self):
        config = self.root / 'sshd_config'
        config.write_text('# preserved\n')
        config.chmod(0o640)

        def command(*args):
            self.commands.append(args)
            if args[:2] == ('sshd', '-T'):
                return 'permitrootlogin prohibit-password\n'
            return ''

        def active(args, **kwargs):
            return subprocess.CompletedProcess(args, 0 if args[-1] == 'ssh.service' else 3)

        with patch.object(safety, 'run', command), patch.object(safety.subprocess, 'run', active):
            safety.ssh_change(config, 'PermitRootLogin', 'prohibit-password')
        self.assertTrue(config.read_text().startswith('PermitRootLogin prohibit-password\n'))
        self.assertIn(('systemctl', 'reload', 'ssh.service'), self.commands)

    def test_ssh_permitrootlogin_invalid_value_refused(self):
        config = self.root / 'sshd_config'
        config.write_text('# preserved\n')
        with patch.object(safety, 'run', self.record):
            for bad in ('maybe', 'Yes', 'root-only', ''):
                with self.assertRaises(ValueError):
                    safety.ssh_change(config, 'PermitRootLogin', bad)
        self.assertEqual(config.read_text(), '# preserved\n')
        self.assertFalse(self.commands)


class UserMenus(Safety):
    def test_users_cli_dispatches_to_safety_helper(self):
        body = '''python3() { printf '%s\\n' "$*" >> "$T/invoked"; }
_fb_user_read_password() { printf 's3cret'; }
select_option() { echo "$CHOICE"; }
system_users add deploy1 || exit 9
system_users passwd deploy1 || exit 9
system_users sudo deploy1 nopasswd || exit 9
system_users unsudo deploy1 || exit 9'''
        self.run_shell('system', body)
        invoked = (self.root / 'invoked').read_text()
        self.assertIn('user-add deploy1', invoked)
        self.assertIn('passwd-set deploy1', invoked)
        self.assertIn('sudo-grant deploy1 nopasswd', invoked)
        self.assertIn('sudo-revoke deploy1', invoked)

    def test_users_list_reports_accounts(self):
        (self.root / 'etc').mkdir(exist_ok=True)
        (self.root / 'etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\ndeploy1:x:1001:1001::/home/deploy1:/bin/bash\n')
        body = '''msg() { printf '%s\\n' "$*" >> "$T/out"; }
system_users list'''
        out = self.run_shell('system', body)
        self.assertIn('deploy1', out)   # awk 账户行直写 stdout
        report = (self.root / 'out').read_text()
        self.assertIn('可登录用户', report)
        self.assertIn('无', report)

    def test_users_invalid_name_refused_before_helper(self):
        body = '''python3() { printf '%s\\n' "$*" > "$T/invoked"; }
system_users add 'Deploy1' || exit 9'''
        self.run_shell('system', body, 9)
        self.assertFalse((self.root / 'invoked').exists())

    def test_hardening_verify_gates_without_local_sshd(self):
        body = '''ssh() { :; }
systemctl() { return 1; }
_fb_hardening_verify_key_login deploy1 /tmp/k; echo "rc=$?"
systemctl() { return 0; }
ssh() { [[ "$1" == -o ]]; }
_fb_hardening_verify_key_login deploy1 /tmp/k; echo "rc=$?"'''
        out = self.run_shell('system', body)
        self.assertIn('rc=2', out)
        self.assertIn('rc=0', out)

    def test_hardening_policy_never_applies_without_verification(self):
        body = '''confirm() { read -r ans || return 1; [[ "$ans" =~ ^[Yy]$ ]]; }
python3() { printf '%s\\n' "$*" >> "$T/py"; }
select_option() { echo "$CHOICE"; }
printf 'n\\n' | _fb_hardening_root_policy deploy1 no; rc=$?
[[ $rc -ne 0 ]] || exit 7
exit 0'''
        self.run_shell('system', body)
        self.assertFalse((self.root / 'py').exists())

    def test_hardening_policy_applies_after_verification(self):
        body = '''python3() { printf '%s\\n' "$*" >> "$T/py"; }
select_option() { echo "$CHOICE"; }
CHOICE=1 _fb_hardening_root_policy deploy1 yes || exit 9
CHOICE=2 _fb_hardening_root_policy deploy1 yes || exit 9'''
        self.run_shell('system', body)
        applied = (self.root / 'py').read_text()
        self.assertIn('PermitRootLogin prohibit-password', applied)
        self.assertIn('PermitRootLogin no', applied)
        self.assertEqual(applied.count('PermitRootLogin'), 2)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Transactions)
    suite.addTests(UserMenus(name) for name in UserMenus.__dict__ if name.startswith('test_'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
