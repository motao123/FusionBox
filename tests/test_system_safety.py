"""Temporary files only; activation and swap commands are mocked."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from test_safety import Safety, ROOT

spec = importlib.util.spec_from_file_location('system_safety', ROOT / 'src/lib/system_safety.py')
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


@unittest.skipIf(os.name == 'nt', 'POSIX ownership and daemon checks run on isolated Linux')
class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fusionbox-safety-')
        self.root = Path(self.tmp.name)
        self.config = self.root / 'sshd_config'
        self.config.write_text('# preserved\n')
        self.config.chmod(0o640)
        self.commands = []

    def tearDown(self):
        self.tmp.cleanup()

    def command(self, *args):
        self.commands.append(args)
        if args[:2] == ('sshd', '-T'):
            return 'passwordauthentication no\nport 2222\n'
        return ''

    def active(self, args, **kwargs):
        return subprocess.CompletedProcess(args, 0 if args[-1] == 'ssh.service' else 3)

    def test_ssh_missing_directive_and_permissions(self):
        with patch.object(safety, 'run', self.command), patch.object(safety.subprocess, 'run', self.active):
            safety.ssh_change(self.config, 'PasswordAuthentication', 'no')
        self.assertTrue(self.config.read_text().startswith('PasswordAuthentication no\n'))
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
        self.assertIn(('systemctl', 'reload', 'ssh.service'), self.commands)
        self.assertTrue(list(self.root.glob('.fusionbox-backup-*/sshd_config')))

    def test_ssh_validation_failure_rolls_back_without_reload(self):
        def fail(*args):
            self.commands.append(args)
            if self.config.read_text().startswith('Port'):
                raise subprocess.CalledProcessError(1, args)
            return ''
        with patch.object(safety, 'run', fail), patch.object(safety.subprocess, 'run', self.active):
            with self.assertRaises(subprocess.CalledProcessError):
                safety.ssh_change(self.config, 'Port', '2222')
        self.assertEqual(self.config.read_text(), '# preserved\n')
        self.assertFalse(any(c[0] == 'systemctl' for c in self.commands))

    def test_ssh_reload_failure_restores_and_retries_old(self):
        def fail(*args):
            result = self.command(*args)
            if args[0] == 'systemctl' and self.config.read_text().startswith('Port'):
                raise subprocess.CalledProcessError(1, args)
            return result
        with patch.object(safety, 'run', fail), patch.object(safety.subprocess, 'run', self.active):
            with self.assertRaises(subprocess.CalledProcessError):
                safety.ssh_change(self.config, 'Port', '2222')
        self.assertEqual(self.config.read_text(), '# preserved\n')
        self.assertEqual(sum(c[0] == 'systemctl' for c in self.commands), 2)

    def test_ssh_effective_override_refused(self):
        with patch.object(safety, 'run', return_value='port 2222\nport 22\n'), patch.object(safety.subprocess, 'run', self.active):
            with self.assertRaises(ValueError):
                safety.ssh_change(self.config, 'Port', '2222')
        self.assertEqual(self.config.read_text(), '# preserved\n')

    def test_ssh_include_match_refused(self):
        included = self.root / 'included.conf'
        included.write_text('Match User root\n PasswordAuthentication yes\n')
        self.config.write_text(f'Include {included}\n')
        with patch.object(safety, 'run') as command:
            with self.assertRaises(ValueError):
                safety.ssh_change(self.config, 'PasswordAuthentication', 'no')
        command.assert_not_called()

    def test_ssh_socket_activation_refused(self):
        with patch.object(safety, 'run', self.command), patch.object(safety.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaises(ValueError):
                safety.ssh_change(self.config, 'Port', '2222')
        self.assertEqual(self.config.read_text(), '# preserved\n')

    def test_login_alert_install_status_and_uninstall(self):
        pam = self.root / 'pam-sshd'
        pam.write_text('# existing pam policy\n')
        script = self.root / 'fusionbox-login-alert'
        conf = self.root / 'notify.conf'
        conf.write_text('TG_BOT_TOKEN=123:valid_token\nTG_CHAT_ID=-456\n')
        conf.chmod(0o600)
        state = self.root / 'login-alert.json'
        with patch.object(safety.shutil, 'which', side_effect=lambda name: '/usr/sbin/sshd' if name == 'sshd' else None), patch.object(safety, 'run', return_value=''):
            safety.login_alert('install', pam, script, conf, state)
        self.assertIn(safety.LOGIN_CONTROL, pam.read_text())
        self.assertEqual(script.stat().st_mode & 0o777, 0o755)
        generated = script.read_text()
        self.assertNotIn('123:valid_token', generated)
        self.assertIn('|| exit 0', generated)
        with patch.object(safety.shutil, 'which', side_effect=lambda name: '/usr/sbin/sshd' if name == 'sshd' else None), patch.object(safety, 'run', return_value=''):
            safety.login_alert('install', pam, script, conf, state)
        self.assertEqual(pam.read_text().count(safety.LOGIN_MARKER), 1)
        record = __import__('json').loads(state.read_text())
        self.assertEqual(record['script']['sha256'], __import__('hashlib').sha256(script.read_bytes()).hexdigest())
        with patch.object(safety.shutil, 'which', side_effect=lambda name: '/usr/sbin/sshd' if name == 'sshd' else None), patch.object(safety, 'run', return_value=''):
            safety.login_alert('uninstall', pam, script, conf, state)
        self.assertEqual(pam.read_text(), '# existing pam policy\n')
        self.assertFalse(script.exists())
        self.assertTrue(conf.exists())

    def test_login_alert_refuses_foreign_script_and_insecure_config(self):
        pam = self.root / 'pam-sshd'; pam.write_text('# pam\n')
        script = self.root / 'fusionbox-login-alert'; script.write_text('#!/bin/bash\nforeign\n'); script.chmod(0o755)
        conf = self.root / 'notify.conf'; conf.write_text('TG_BOT_TOKEN=123:valid\nTG_CHAT_ID=456\n'); conf.chmod(0o644)
        state = self.root / 'login-alert.json'
        with self.assertRaises(ValueError):
            safety.login_alert('install', pam, script, conf, state)
        self.assertEqual(pam.read_text(), '# pam\n')
        self.assertEqual(script.read_text(), '#!/bin/bash\nforeign\n')

    def test_login_alert_runtime_hides_credentials_and_fails_open(self):
        pam = self.root / 'pam-sshd'; pam.write_text('# pam\n')
        script = self.root / 'fusionbox-login-alert'
        conf = self.root / 'notify.conf'
        conf.write_text('TG_BOT_TOKEN=123:secret_token\nTG_CHAT_ID=-456\n'); conf.chmod(0o600)
        state = self.root / 'login-alert.json'
        with patch.object(safety.shutil, 'which', side_effect=lambda name: '/usr/sbin/sshd' if name == 'sshd' else None), patch.object(safety, 'run', return_value=''):
            safety.login_alert('install', pam, script, conf, state)
        mockbin = self.root / 'mockbin'; mockbin.mkdir()
        curl = mockbin / 'curl'
        curl.write_text("#!/bin/bash\nprintf '%s\\n' \"$*\" > \"$CAPTURE\"\nprintf '{\\\"ok\\\":false}'\n")
        curl.chmod(0o755)
        capture = self.root / 'argv'
        env = os.environ.copy(); env.update({'PATH': str(mockbin) + os.pathsep + env['PATH'], 'CAPTURE': str(capture),
                                             'PAM_TYPE': 'open_session', 'PAM_USER': 'alice', 'PAM_RHOST': '203.0.113.9'})
        result = subprocess.run([str(script)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('secret_token', capture.read_text())
        self.assertNotIn('-456', capture.read_text())

    def test_login_alert_refuses_managed_drift(self):
        pam = self.root / 'pam-sshd'; pam.write_text('# pam\n')
        script = self.root / 'fusionbox-login-alert'
        conf = self.root / 'notify.conf'; conf.write_text('TG_BOT_TOKEN=123:valid\nTG_CHAT_ID=456\n'); conf.chmod(0o600)
        state = self.root / 'login-alert.json'
        with patch.object(safety.shutil, 'which', side_effect=lambda name: '/usr/sbin/sshd' if name == 'sshd' else None), patch.object(safety, 'run', return_value=''):
            safety.login_alert('install', pam, script, conf, state)
        script.write_text(script.read_text() + '# drift\n')
        with self.assertRaises(ValueError):
            safety.login_alert('uninstall', pam, script, conf, state)
        self.assertTrue(script.exists()); self.assertTrue(state.exists())

    def test_thp_current_requires_one_active_mode(self):
        thp = self.root / 'thp'
        thp.write_text('always [madvise] never\n')
        self.assertEqual(safety._thp_current(thp), 'madvise')
        for invalid in ('always madvise never\n', '[always] [never]\n'):
            thp.write_text(invalid)
            with self.assertRaises(ValueError):
                safety._thp_current(thp)

    def test_unit_absent_restore_never_calls_systemctl(self):
        unit = self.root / 'fusionbox-thp.service'
        with patch.object(safety, 'run') as command, patch.object(safety.shutil, 'which', return_value='/bin/systemctl'):
            safety._restore_unit_state({'exists': False}, unit)
        command.assert_not_called()
        self.assertFalse(unit.exists())

    def test_tuning_second_apply_failure_restores_snapshot_bytes(self):
        etc, state, thp = self._tuning_paths()
        runtime = {key: '7' for key in safety._tuning_values('stream', 8 * 1024 * 1024)}
        fail = False
        def command(*args):
            if args[:2] == ('sysctl', '-n'):
                return runtime[args[2]]
            if args[:2] == ('sysctl', '-p'):
                for line in Path(args[2]).read_text().splitlines():
                    if line and not line.startswith('#'):
                        key, value = line.split('=', 1); runtime[key.strip()] = value.strip()
                if fail and '99-fusionbox-tuning.conf' in args[2]:
                    raise subprocess.CalledProcessError(1, args)
                return ''
            return ''
        with patch.object(safety, 'run', command), patch.object(safety.shutil, 'which', return_value=None):
            safety.tuning('apply', 'balanced', etc, state, thp)
            snapshot = (state / 'snapshot.json').read_bytes()
            fail = True
            with self.assertRaises(subprocess.CalledProcessError):
                safety.tuning('apply', 'web', etc, state, thp)
        self.assertEqual((state / 'snapshot.json').read_bytes(), snapshot)
        self.assertIn('# profile: balanced', (etc / 'sysctl.d/99-fusionbox-tuning.conf').read_text())

    def _tuning_paths(self):
        etc = self.root / 'etc'
        for directory in ('sysctl.d', 'security/limits.d', 'systemd/system'):
            (etc / directory).mkdir(parents=True, exist_ok=True)
        return etc, self.root / 'state', self.root / 'missing-thp'

    def test_tuning_apply_switch_and_restore(self):
        etc, state, thp = self._tuning_paths()
        runtime = {key: '7' for key in safety._tuning_values('stream', 8 * 1024 * 1024)}
        original = runtime.copy()
        def command(*args):
            if args[:2] == ('sysctl', '-n'):
                if args[2] not in runtime:
                    raise subprocess.CalledProcessError(1, args)
                return runtime[args[2]]
            if args[:2] == ('sysctl', '-p'):
                for line in Path(args[2]).read_text().splitlines():
                    if line and not line.startswith('#'):
                        key, value = line.split('=', 1); runtime[key.strip()] = value.strip()
                return ''
            return ''
        with patch.object(safety, 'run', command), patch.object(safety.shutil, 'which', return_value=None):
            safety.tuning('apply', 'balanced', etc, state, thp)
            snapshot = (state / 'snapshot.json').read_text()
            safety.tuning('apply', 'web', etc, state, thp)
            self.assertIn('# profile: web', (etc / 'sysctl.d/99-fusionbox-tuning.conf').read_text())
            current = __import__('json').loads((state / 'snapshot.json').read_text())
            self.assertEqual(current['managed'][str(etc / 'sysctl.d/99-fusionbox-tuning.conf')]['sha256'],
                             __import__('hashlib').sha256((etc / 'sysctl.d/99-fusionbox-tuning.conf').read_bytes()).hexdigest())
            self.assertIn('"vm.swappiness": "7"', snapshot)
            safety.tuning('restore', etc=etc, state_dir=state, thp=thp)
        self.assertEqual(runtime, original)
        self.assertFalse((etc / 'sysctl.d/99-fusionbox-tuning.conf').exists())
        self.assertFalse((etc / 'security/limits.d/99-fusionbox-tuning.conf').exists())
        self.assertFalse((state / 'snapshot.json').exists())

    def test_tuning_failure_rolls_back_and_refuses_external_file(self):
        etc, state, thp = self._tuning_paths()
        target = etc / 'sysctl.d/99-fusionbox-tuning.conf'
        target.write_text('administrator content\n')
        with patch.object(safety, 'run') as command, self.assertRaises(ValueError):
            safety.tuning('apply', 'high', etc, state, thp)
        command.assert_not_called()
        target.unlink()
        runtime = {key: '9' for key in safety._tuning_values('high', 8 * 1024 * 1024)}
        original = runtime.copy()
        calls = 0
        def command(*args):
            nonlocal calls
            if args[:2] == ('sysctl', '-n'):
                return runtime[args[2]]
            if args[:2] == ('sysctl', '-p'):
                calls += 1
                for line in Path(args[2]).read_text().splitlines():
                    if line and not line.startswith('#'):
                        key, value = line.split('=', 1); runtime[key.strip()] = value.strip()
                if calls == 1:
                    raise subprocess.CalledProcessError(1, args)
                return ''
            return ''
        with patch.object(safety, 'run', command), patch.object(safety.shutil, 'which', return_value=None), self.assertRaises(subprocess.CalledProcessError):
            safety.tuning('apply', 'high', etc, state, thp)
        self.assertEqual(runtime, original)
        self.assertFalse(target.exists())
        self.assertFalse((state / 'snapshot.json').exists())

    def test_real_key_parsing_and_physical_delete(self):
        key = self.root / 'key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        public = key.with_suffix('.pub').read_text()
        authorized = self.root / 'authorized_keys'
        authorized.write_text('# comment\n  # indented\n\nssh-ed25519 invalid\n' + public + 'restrict ' + public)
        self.assertEqual([n for n, _ in safety.valid_keys(authorized)], [5])
        safety.keys_action(authorized, 'delete', 5)
        self.assertIn('restrict ', authorized.read_text())
        with self.assertRaises(ValueError):
            safety.keys_action(authorized, 'check')

    def test_invalid_key_add_preserves_existing(self):
        with self.assertRaises(ValueError):
            safety.keys_add(self.config, 'ssh-ed25519 AAAA invalid')
        self.assertEqual(self.config.read_text(), '# preserved\n')

    def swap_setup(self):
        swap = self.root / 'swapfile'
        swap.write_text('swap bytes'); swap.chmod(0o600)
        fstab = self.root / 'fstab'
        original = f'# {swap}\n{swap} none swap sw 0 0\n/other-swapfile none swap sw 0 0\n'
        fstab.write_text(original)
        return swap, fstab, original

    def test_swapoff_failure_never_removes(self):
        swap, fstab, original = self.swap_setup()
        def command(*args):
            if args[0] == 'swapoff':
                raise subprocess.CalledProcessError(1, args)
            return str(swap) + '\n'
        with patch.object(safety, 'run', command), self.assertRaises(subprocess.CalledProcessError):
            safety.swap_remove(swap, fstab)
        self.assertTrue(swap.exists()); self.assertEqual(fstab.read_text(), original)

    def test_swap_remaining_active_never_removes(self):
        swap, fstab, original = self.swap_setup()
        with patch.object(safety, 'run', return_value=str(swap) + '\n'), self.assertRaises(ValueError):
            safety.swap_remove(swap, fstab)
        self.assertTrue(swap.exists()); self.assertEqual(fstab.read_text(), original)

    def test_swap_preserves_other_entries_and_comments(self):
        swap, fstab, original = self.swap_setup()
        with patch.object(safety, 'run', side_effect=[str(swap) + '\n', '', '/other-swapfile\n']):
            safety.swap_remove(swap, fstab)
        self.assertFalse(swap.exists())
        self.assertEqual(fstab.read_text(), f'# {swap}\n/other-swapfile none swap sw 0 0\n')

    def test_swap_alias_and_symlink_refused(self):
        swap, fstab, original = self.swap_setup()
        alias = self.root / 'alias'; alias.symlink_to(swap)
        with patch.object(safety, 'run', return_value=str(alias) + '\n'), self.assertRaises(ValueError):
            safety.swap_remove(swap, fstab)
        with self.assertRaises(ValueError):
            safety.swap_remove(alias, fstab)
        self.assertEqual(fstab.read_text(), original)

    def test_swap_file_delete_failure_restores_fstab(self):
        swap, fstab, original = self.swap_setup()
        unlink = Path.unlink
        def fail(path, *args, **kwargs):
            if path == swap:
                raise OSError('injected')
            return unlink(path, *args, **kwargs)
        with patch.object(safety, 'run', return_value=''), patch.object(Path, 'unlink', fail), self.assertRaises(OSError):
            safety.swap_remove(swap, fstab)
        self.assertEqual(fstab.read_text(), original); self.assertTrue(swap.exists())

    def f2b_setup(self):
        directory = self.root / 'fail2ban'; (directory / 'jail.d').mkdir(parents=True)
        (directory / 'jail.local').write_text('[sshd]\nenabled = false\n')
        return directory, directory / 'jail.d/99-fusionbox-sshd.local'

    def test_fail2ban_dedicated_file_preserves_global(self):
        directory, target = self.f2b_setup()
        with patch.object(safety, 'run', self.command):
            safety.fail2ban_change(directory, '5', '3600')
        self.assertEqual((directory / 'jail.local').read_text(), '[sshd]\nenabled = false\n')
        self.assertIn('maxretry = 5', target.read_text())
        self.assertNotIn('[DEFAULT]', target.read_text())

    def test_fail2ban_collision_and_invalid_numbers(self):
        directory, target = self.f2b_setup()
        target.write_text('unknown')
        with patch.object(safety, 'run') as command:
            for retry in ('5', '0', '-1', '5\nenabled=true'):
                with self.assertRaises(ValueError):
                    safety.fail2ban_change(directory, retry, '3600')
        command.assert_not_called(); self.assertEqual(target.read_text(), 'unknown')

    def test_fail2ban_stage_validation_failure(self):
        directory, target = self.f2b_setup()
        with patch.object(safety, 'run', side_effect=subprocess.CalledProcessError(1, [])), self.assertRaises(subprocess.CalledProcessError):
            safety.fail2ban_change(directory, '5', '3600')
        self.assertFalse(target.exists())

    def test_fail2ban_reload_failure_restores_old(self):
        directory, target = self.f2b_setup()
        original = '# FusionBox managed sshd parameters v1\n[sshd]\nmaxretry = 9\n'
        target.write_text(original)
        def command(*args):
            self.commands.append(args)
            if args == ('fail2ban-client', 'reload') and 'maxretry = 5' in target.read_text():
                raise subprocess.CalledProcessError(1, args)
            return ''
        with patch.object(safety, 'run', command), self.assertRaises(subprocess.CalledProcessError):
            safety.fail2ban_change(directory, '5', '3600')
        self.assertEqual(target.read_text(), original)
        self.assertEqual(self.commands.count(('fail2ban-client', 'reload')), 2)

    def test_real_fail2ban_staged_configuration(self):
        binary = shutil.which('fail2ban-client')
        if not binary or not os.path.isdir('/etc/fail2ban'):
            # CI/容器里通常两者都没有；此时本测试无法验证任何东西，如实跳过。
            self.skipTest('fail2ban-client or /etc/fail2ban unavailable; mocked rollback coverage remains')
        directory = self.root / 'real-fail2ban'
        shutil.copytree('/etc/fail2ban', directory)
        # Isolate logs/backend and enable only a file-backed sshd jail; validation only.
        log = self.root / 'auth.log'; log.write_text('')
        (directory / 'jail.local').write_text('[DEFAULT]\nbackend = polling\n[sshd]\nenabled = true\nlogpath = ' + str(log) + '\n')
        actual = safety.run
        def command(*args):
            if args == ('fail2ban-client', 'reload'):
                return ''
            return actual(*args)
        with patch.object(safety, 'run', command):
            safety.fail2ban_change(directory, '7', '1200')
        self.assertIn('maxretry = 7', (directory / 'jail.d/99-fusionbox-sshd.local').read_text())

    def test_real_sshd_t_with_generated_config(self):
        binary = shutil.which('sshd')
        if not binary:
            self.skipTest('sshd unavailable; never install or edit host authentication')
        key = self.root / 'host_key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        self.config.write_text(f'HostKey {key}\nPidFile {self.root}/sshd.pid\nUsePAM no\n')

        # 环境自检：CI/容器里常常没有特权分离目录 /run/sshd，此时 sshd -t 对**任何**
        # 配置都返回 255（与配置内容无关）。以 root 运行时先补齐它，让测试真正走到
        # 校验路径；补不上就如实跳过——本测试要验证的是 FusionBox 的事务处理，
        # 不是「这台机器装好了 sshd」，环境不具备时伪装通过才是真的有害。
        privsep = '/run/sshd'
        if os.geteuid() == 0 and not os.path.isdir(privsep):
            try:
                os.makedirs(privsep, mode=0o755, exist_ok=True)
            except OSError:
                pass
        probe = subprocess.run([binary, '-t', '-f', str(self.config)],
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if probe.returncode != 0:
            detail = (probe.stderr or probe.stdout or '').strip().splitlines()
            self.skipTest('sshd -t cannot validate even a minimal config in this environment: '
                          + (detail[-1] if detail else 'exit %d' % probe.returncode))

        actual = safety.run
        def command(*args):
            if args[0] == 'systemctl':
                return ''
            return actual(binary, *args[1:])
        # Only mock unit discovery. sshd checks remain real subprocesses.
        def dispatch(args, **kwargs):
            if args[0] == 'systemctl':
                return self.active(args, **kwargs)
            return real_subprocess(args, **kwargs)
        real_subprocess = subprocess.run
        with patch.object(safety, 'run', command), patch.object(safety.subprocess, 'run', dispatch):
            safety.ssh_change(self.config, 'PasswordAuthentication', 'no')
        output = actual(binary, '-T', '-f', str(self.config))
        self.assertIn('passwordauthentication no', output)


class LegacyMenus(Safety):
    def test_disabled_port_control_never_calls_firewall(self):
        self.run_shell('panels', 'iptables() { touch "$T/firewall"; }; ufw() { touch "$T/firewall"; }; panels_docker_port_control', 1)
        self.assertFalse((self.root / 'firewall').exists())

    def test_docker_partial_export_not_published(self):
        self.run_shell('panels', 'docker() { printf partial; return 9; }; _panels_docker_archive "$T/backups/test.tar" export test', 1)
        self.assertFalse((self.root / 'backups/test.tar').exists())
        self.assertFalse(list((self.root / 'backups').glob('.fusionbox-export-*')))

    def test_docker_old_target_preserved(self):
        target = self.root / 'backups/test.tar'; target.write_text('old')
        self.run_shell('panels', 'docker() { touch "$T/called"; }; _panels_docker_archive "$T/backups/test.tar" save image', 1)
        self.assertEqual(target.read_text(), 'old'); self.assertFalse((self.root / 'called').exists())

    def test_docker_success_publishes_valid_tar(self):
        self.run_shell('panels', 'docker() { tar -cf - -C "$T" etc; }; _panels_docker_archive "$T/backups/test.tar" export test')
        self.assertTrue((self.root / 'backups/test.tar').exists())

    def test_docker_failed_export_never_transfers(self):
        module = self.root / 'panels.sh'
        module.write_text(module.read_text().replace('/root/docker_backups', self.posix + '/backups'))
        self.run_shell('panels', 'docker() { printf partial; return 9; }; scp() { touch "$T/scp"; }; panels_docker_backup <<< $\'7\\ntest\\nuser@example.test\'', 1)
        self.assertFalse((self.root / 'scp').exists())

    def test_nginx_reload_failure_restores_bytes(self):
        directory = self.root / 'etc/nginx'; directory.mkdir()
        config = directory / 'nginx.conf'; config.write_text('worker_processes 1;\nhttp {\n}\n')
        original = config.read_bytes()
        self.run_shell('web', 'nginx() { [[ "$1" == -t ]]; }; web_optimize', 1)
        self.assertEqual(config.read_bytes(), original)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Transactions)
    suite.addTests(LegacyMenus(name) for name in LegacyMenus.__dict__ if name.startswith('test_'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
