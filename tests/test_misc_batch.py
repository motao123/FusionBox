"""Misc batch tests: psABI, sshkey import, ssh out-collections, work sessions, clamav scan."""
import os
from test_safety import Safety


class Psabi(Safety):
    def test_psabi_levels(self):
        body = '''[[ "$(_psabi_from_flags "fpu sse")" == "v1" ]] || exit 9
[[ "$(_psabi_from_flags "fpu sse4_1 sse4_2 popcnt ssse3")" == "v2" ]] || exit 9
[[ "$(_psabi_from_flags "sse4_2 popcnt ssse3 sse4_1 avx2 bmi2 bmi fma movbe")" == "v3" ]] || exit 9
[[ "$(_psabi_from_flags "avx2 fma bmi2 bmi movbe popcnt sse4_1 sse4_2 ssse3 avx512f avx512bw avx512cd avx512dq avx512vl")" == "v4" ]] || exit 9'''
        self.run_shell('system', body)


class SshOut(Safety):
    def body(self, extra):
        return extra

    def test_add_list_rm_roundtrip(self):
        body = '''cluster_sshout add prod root@203.0.113.9 2200 || exit 9
cluster_sshout add stage deploy@example.test || exit 9
cluster_sshout list'''
        out = self.run_shell('cluster', self.body(body))
        self.assertIn('prod -> root@203.0.113.9:2200', out)
        self.assertIn('stage -> deploy@example.test:22', out)
        conf = self.root / 'etc/fusionbox/ssh_out.conf'
        if os.name != 'nt':
            self.assertEqual(conf.stat().st_mode & 0o777, 0o600)

    def test_add_rejects_injection_shapes(self):
        body = '''cluster_sshout add 'bad name' root@host || exit 9
cluster_sshout add ok2 'root@host; rm -rf /' || exit 9
cluster_sshout add ok3 root@host 99999 || exit 9'''
        self.run_shell('cluster', self.body(body), 9)
        self.assertFalse((self.root / 'etc/fusionbox/ssh_out.conf').exists())

    def test_rm_and_connect(self):
        body = ('cluster_sshout add prod root@203.0.113.9 2200 || exit 9\n'
                'ssh() { printf "ssh %s\\n" "$*" >> "$T/ssh"; return 0; }\n'
                'cluster_sshout connect prod || exit 9\n'
                'cluster_sshout rm prod || exit 9\n'
                'cluster_sshout rm prod || exit 9')
        self.run_shell('cluster', self.body(body), 9)
        ssh = (self.root / 'ssh').read_text()
        self.assertIn('-t -p 2200 root@203.0.113.9', ssh)
        conf = self.root / 'etc/fusionbox/ssh_out.conf'
        if os.name != 'nt':
            self.assertEqual(conf.stat().st_mode & 0o777, 0o600)
        self.assertEqual(conf.read_text().strip(), '')


class WorkSessions(Safety):
    def tmux_mock(self):
        return ('tmux() { case "$1 $2" in\n'
                '  "has-session -t") [[ -f "$T/tmux-$3" ]];;\n'
                '  "new-session -d") printf "new %s\\n" "$3 $4" >> "$T/tmux"; touch "$T/tmux-$4"; return 0;;\n'
                '  "send-keys -t") printf "send %s %s C-m\\n" "$3" "$4" >> "$T/tmux"; return 0;;\n'
                '  "kill-session -t") printf "kill %s\\n" "$3" >> "$T/tmux"; rm -f "$T/tmux-$3"; return 0;;\n'
                '  *) return 0;; esac; }\n')

    def test_new_send_kill_flow(self):
        body = self.tmux_mock() + '''workspace_work new 3 || exit 9
workspace_work send 3 "echo hi" || exit 9
confirm() { return 0; }
workspace_work kill 3 || exit 9'''
        self.run_shell('workspace', body)
        lines = (self.root / 'tmux').read_text().strip().splitlines()
        # 槽位 3 的会话名由实现决定（曾为 work3，现为 w3）。这里断言的是真正的不变量：
        # new/send/kill 三处必须使用同一个槽位名，且名字指向槽位 3。把品牌字符串写死，
        # 会在命名演进时变成一个与被测行为无关的假失败。
        self.assertRegex(lines[0], r'^new -s (?:work|w)3$')
        session = lines[0].split()[-1]
        self.assertEqual(lines[1], 'send %s echo hi C-m' % session)
        self.assertEqual(lines[2], 'kill %s' % session)

    def test_invalid_number_refused(self):
        body = self.tmux_mock() + '''workspace_work new 11 || exit 9
workspace_work send 0 "x" || exit 9'''
        self.run_shell('workspace', body, 9)

    def test_send_requires_command(self):
        body = self.tmux_mock() + 'workspace_work send 3'
        self.run_shell('workspace', body, 2)


class SshkeyImport(Safety):
    def test_import_url_flow(self):
        body = '''_download() { printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1234567890abcdefghijklmnopqrstuvwxyzAB test@host\\ngarbage-line\\n' > "$2"; return 0; }
python3() { printf 'keys-add %s\\n' "$(head -c 40)" >> "$T/added"; return 0; }
confirm() { return 0; }
_fb_pubkey_valid() { [[ "$1" == ssh-* ]]; }
_fb_sshkey_import_url "https://github.com/someuser.keys" || exit 9'''
        self.run_shell('system', body)
        self.assertIn('keys-add ssh-ed25519', (self.root / 'added').read_text())

    def test_import_refuses_non_https(self):
        body = '''_download() { touch "$2"; return 0; }
_fb_sshkey_import_url "file:///etc/shadow" || exit 9'''
        self.run_shell('system', body, 9)

    def test_import_refuses_empty_download(self):
        body = '''_download() { : > "$2"; return 0; }
_fb_pubkey_valid() { return 1; }
_fb_sshkey_import_url "https://example.test/keys" || exit 9'''
        self.run_shell('system', body, 9)


class ClamavScan(Safety):
    def redirect_log(self):
        module = self.root / 'market.sh'
        module.write_text(module.read_text().replace('/root/clamav-scan-', self.posix + '/clamav-scan-'))

    def test_missing_clamscan_installs_then_scans(self):
        self.redirect_log()
        body = ('command() { if [[ "$2" == clamscan ]]; then return 1; fi; builtin command "$@"; }\n'
                '_install_pkg() { printf "pkg %s\\n" "$*" >> "$T/apt"; return 0; }\n'
                'freshclam() { return 0; }\n'
                'clamscan() { printf "clamscan %s\\n" "$*" >> "$T/cl"; return 0; }\n'
                'confirm() { return 0; }\n'
                'market_clamav /tmp || exit 9')
        self.run_shell('market', body)
        apt = (self.root / 'apt').read_text()
        self.assertIn('pkg clamav', apt)
        self.assertIn('clamscan -ri', (self.root / 'cl').read_text())

    def test_infected_files_propagate_failure(self):
        self.redirect_log()
        body = ('clamscan() { printf "clamscan %s\\n" "$*" >> "$T/cl"; return 1; }\n'
                'command() { if [[ "$2" == clamscan ]]; then return 0; fi; builtin command "$@"; }\n'
                'grep() { builtin grep "$@" 2>/dev/null || return 1; }\n'
                'market_clamav /tmp')
        self.run_shell('market', body, 1)

    def test_missing_path_refused(self):
        body = 'market_clamav /no/such/path'
        self.run_shell('market', body, 2)


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
