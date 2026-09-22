"""Env-file and NIC management tests; ip/editor commands are mocked."""
import os
from pathlib import Path
import unittest
from test_safety import Safety


class EnvMenus(Safety):
    def setUp(self):
        super().setUp()
        self.home = self.root / 'home'
        self.home.mkdir(exist_ok=True)
        (self.home / '.bashrc').write_text('# bashrc\nexport FOO=bar\n')
        (self.root / 'etc/profile.d').mkdir(exist_ok=True)
        (self.root / 'etc/profile.d/00-test.sh').write_text('# profile d\n')

    def body_env(self, extra=''):
        return f'HOME="{self.posix}/home"\nFUSION_CONFIG_DIR="{self.posix}/fbconfig"\n' + extra

    def test_env_list_reports_files_and_syntax(self):
        body = self.body_env('msg() { printf "%s\\n" "$*" >> "$T/out"; }\nsystem_env list')
        self.run_shell('system', body)
        out = (self.root / 'out').read_text()
        self.assertIn('.bashrc', out)
        self.assertIn('语法 OK', out)

    def test_env_show_refuses_non_allowlisted(self):
        body = self.body_env('cat() { printf touched > "$T/cat"; }\nsystem_env show /etc/shadow')
        self.run_shell('system', body, 1)
        self.assertFalse((self.root / 'cat').exists())

    def test_env_show_allows_home_bashrc(self):
        body = self.body_env('system_env show "$HOME/.bashrc"')
        out = self.run_shell('system', body)
        self.assertIn('export FOO=bar', out)

    def test_env_check_detects_broken_file(self):
        (self.home / '.bashrc').write_text('if {\n')
        body = self.body_env('msg_ok() { printf "%s\\n" "$*" >> "$T/out"; }\n'
                             'msg_err() { printf "%s\\n" "$*" >> "$T/out"; }\n'
                             'system_env check')
        self.run_shell('system', body, 1)
        self.assertIn('语法错误', (self.root / 'out').read_text())

    def test_env_backup_returned_path_is_real(self):
        # 回归（v1.43.0）：修复前 _env_backup 两次调用 date，跨秒时返回的
        # 备份路径并不存在，"编辑失败自动恢复"会静默失效
        body = ('date() { if [[ -z "$__d1" ]]; then __d1=1; printf "20260101-000000"; '
                'else printf "20260101-000001"; fi; }\n'
                'p=$(_env_backup "$HOME/.bashrc"); [[ -f "$p" ]] && echo real || echo missing')
        out = self.run_shell('system', body)
        self.assertIn('real', out)

    def test_env_edit_backs_up_and_restores_broken_edit(self):
        editor = self.root / 'editor-broken.sh'
        editor.write_text(f'printf "if {{\\n" >> "{self.posix}/home/.bashrc"\n')
        editor.chmod(0o755)
        body = self.body_env(f'EDITOR="{self.posix}/editor-broken.sh"\n'
                             'confirm() { return 0; }\n'
                             'msg_ok() { printf "%s\\n" "$*" >> "$T/out"; }\n'
                             'system_env edit "$HOME/.bashrc"')
        self.run_shell('system', body)
        self.assertEqual((self.home / '.bashrc').read_text(), '# bashrc\nexport FOO=bar\n')
        backups = list((self.root / 'fbconfig' / 'backups' / 'env').glob('.bashrc.*.bak'))
        self.assertEqual(len(backups), 1)

    def test_env_edit_keeps_valid_edit(self):
        editor = self.root / 'editor-ok.sh'
        editor.write_text(f'printf "export BAR=baz\\n" >> "{self.posix}/home/.bashrc"\n')
        editor.chmod(0o755)
        body = self.body_env(f'EDITOR="{self.posix}/editor-ok.sh"\n'
                             'system_env edit "$HOME/.bashrc" || exit 9')
        self.run_shell('system', body)
        self.assertIn('export BAR=baz', (self.home / '.bashrc').read_text())

    def test_env_edit_refuses_symlink(self):
        (self.home / '.bashrc').unlink()
        try:
            (self.home / '.bashrc').symlink_to(self.root / 'etc' / 'profile')
        except OSError:
            self.skipTest('symlink privilege unavailable; exercised on Linux CI/server')
        body = self.body_env('EDITOR=true\nsystem_env edit "$HOME/.bashrc" || exit 9')
        self.run_shell('system', body, 9)


class NicMenus(Safety):
    def ip_mock(self, dev='ens3'):
        return (f'ip() {{\n'
                f'  case "$*" in\n'
                f'    "-br addr") printf "%-12s UP %s\\n" "{dev}" "192.0.2.10";;\n'
                f'    "link show dev "*) [[ "$4" == "{dev}" || "$4" == "lo" ]];;\n'
                f'    "route show default") printf "default via 192.0.2.1 dev {dev}\\n";;\n'
                f'    "addr show dev "*) printf "addr show {dev}\\n";;\n'
                f'    "-s link show "*) printf "stats {dev}\\n";;\n'
                f'    "link set dev "*) printf "%s %s\\n" "$4" "$5" >> "$T/linkset";;\n'
                f'    *) return 1;;\n'
                f'  esac\n'
                f'}}\n')

    def test_nic_list_shows_interfaces(self):
        body = self.ip_mock() + 'msg() { printf "%s\\n" "$*" >> "$T/out"; }\n_nic_list'
        self.run_shell('network', body)
        out = (self.root / 'out').read_text()
        self.assertIn('ens3', out)
        self.assertIn('默认路由网卡: ens3', out)

    def test_nic_info_validates_device(self):
        body = self.ip_mock() + '_nic_info "not-exist" || exit 9'
        self.run_shell('network', body, 9)
        body = self.ip_mock() + '_nic_info "bad name; rm" || exit 9'
        self.run_shell('network', body, 9)

    def test_nic_info_shows_details(self):
        body = self.ip_mock() + 'ethtool() { printf "Speed: 1000Mb/s\\n"; }\n' \
            'msg() { printf "%s\\n" "$*" >> "$T/out"; }\n_nic_info ens3'
        out = self.run_shell('network', body)
        self.assertIn('addr show ens3', out)
        self.assertIn('stats ens3', out)
        self.assertIn('Speed: 1000Mb/s', out)

    def test_nic_down_default_route_requires_confirm(self):
        body = self.ip_mock() + 'confirm() { return 1; }\n_nic_toggle down ens3 || exit 9'
        self.run_shell('network', body, 9)
        self.assertFalse((self.root / 'linkset').exists())

    def test_nic_down_confirmed_executes(self):
        body = self.ip_mock() + 'confirm() { return 0; }\n_nic_toggle down ens3 || exit 9'
        self.run_shell('network', body)
        self.assertIn('ens3 down', (self.root / 'linkset').read_text())

    def test_nic_up_non_default_no_confirm_needed(self):
        body = self.ip_mock(dev='lo') + '_nic_toggle up lo || exit 9'
        self.run_shell('network', body)
        self.assertIn('lo up', (self.root / 'linkset').read_text())

    def test_nic_toggle_rejects_unknown_device(self):
        body = self.ip_mock() + '_nic_toggle down wifi9 || exit 9'
        self.run_shell('network', body, 9)
        self.assertFalse((self.root / 'linkset').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
