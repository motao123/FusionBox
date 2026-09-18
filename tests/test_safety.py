"""Behavioral safety tests. All writable system paths are redirected to a temp tree."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Safety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fusionbox-test-')
        self.root = Path(self.tmp.name)
        self.posix = self.root.as_posix()
        if os.name == 'nt':
            self.posix = '/' + self.posix[0].lower() + self.posix[2:]
        for d in ('etc/fusionbox', 'etc/sysctl.d', 'opt/games/demo', 'backups', 'bin'):
            (self.root / d).mkdir(parents=True)
        self.modules = {}
        for name in ('system', 'web', 'cluster', 'network', 'panels'):
            text = (ROOT / f'src/modules/{name}.sh').read_text(encoding='utf-8')
            for prefix in ('/etc/', '/opt/', '/var/', '/usr/local/'):
                text = text.replace(prefix, self.posix + prefix)
            target = self.root / f'{name}.sh'
            target.write_text(text, encoding='utf-8')
            self.modules[name] = self.posix + '/' + target.name

    def tearDown(self):
        self.tmp.cleanup()

    def run_shell(self, name, body, expected=0):
        prelude = '\n'.join(f'{n}() {{ :; }}' for n in ('msg', 'msg_err', 'msg_ok', 'msg_warn', 'msg_info', 'msg_tip', 'msg_title', '_log_write', 'pause', '_require_root'))
        if os.name == 'nt':
            prelude += '\npython3() { "' + sys.executable.replace('\\', '/') + '" "$@"; }'
        script = f'source "{self.modules[name]}"\n{prelude}\nconfirm() {{ return 0; }}\nT="{self.posix}"\n{body}\n'
        env = os.environ.copy()
        if os.name == 'nt':
            env['FB_SRC'] = str(self.root / 'input.json')
        result = subprocess.run(['bash'], input=script, text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_mirror_merge_preserves_unrelated_keys(self):
        src = self.root / 'input.json'
        src.write_text('{"log-driver":"local","ipv6":true}')
        self.run_shell('panels', '_panels_docker_mirror_merge set "$T/input.json" "$T/out.json" python3 https://example.test')
        self.assertEqual(json.loads((self.root / 'out.json').read_text()), {'log-driver': 'local', 'ipv6': True, 'registry-mirrors': ['https://example.test']})
        self.run_shell('panels', '_panels_docker_mirror_merge clear "$T/out.json" "$T/clear.json" python3')
        self.assertEqual(json.loads((self.root / 'clear.json').read_text()), {'log-driver': 'local', 'ipv6': True})

    def test_benchmark_failure_propagates(self):
        self.run_shell('network', '_download() { printf "exit 37\\n" > "$2"; }; _network_bench_execute demo demo https://example.test normal auto', 37)

    def test_game_volume_project_prefix(self):
        out = self.run_shell('cluster', '''docker() { case "$1 $2" in
"compose config") printf '%s' '{"volumes":{"data":{"name":"project_data"}}}';;
"volume inspect") [[ "$3" == project_data ]];; *) return 9;; esac; }
_game_resolve_volume demo data''')
        self.assertEqual(out, 'project_data')

    def test_game_unknown_volume_fails(self):
        self.run_shell('cluster', 'docker() { printf "{}"; }; _game_resolve_volume demo missing', 1)

    def test_game_missing_real_volume_fails(self):
        self.run_shell('cluster', '''docker() { [[ "$1" == compose ]] && { printf '%s' '{"volumes":{"data":{"name":"project_data"}}}'; return; }; return 1; }
_game_resolve_volume demo data''', 1)

    def test_restore_rejects_traversal_before_stop(self):
        archive = self.root / 'backups/demo-unsafe.tar.gz'
        with tarfile.open(archive, 'w:gz') as out:
            entry = tarfile.TarInfo('../escape'); entry.size = 1
            out.addfile(entry, io.BytesIO(b'x'))
        self.run_shell('cluster', '''CLUSTER_GAME_BACKUP_DIR="$T/backups"
_game_resolve_volume() { printf project_data; }
_game_ensure_alpine() { return 0; }
docker() { touch "$T/docker-called"; return 1; }
_game_restore demo data <<< 1''', 1)
        self.assertFalse((self.root / 'docker-called').exists())

    def test_dns_symlink_preserved(self):
        target = self.root / 'dns-target'; target.write_text('nameserver 127.0.0.53\n')
        try:
            (self.root / 'etc/resolv.conf').symlink_to(target)
        except OSError:
            self.skipTest('symlink privilege unavailable; exercised on Linux CI/server')
        self.run_shell('system', '_system_dns_apply 1.1.1.1', 1)
        self.run_shell('system', '_system_dns_restore', 1)
        self.assertTrue((self.root / 'etc/resolv.conf').is_symlink())
        self.assertEqual(target.read_text(), 'nameserver 127.0.0.53\n')

    def test_existing_certbot_timer_detected(self):
        result = self.run_shell('web', 'systemctl() { [[ "$2" == certbot.timer ]]; }; _web_ssl_existing_schedule')
        self.assertEqual(result, 'certbot.timer')

    def test_renew_failure_propagates(self):
        self.run_shell('web', 'certbot() { return 23; }; web_ssl_renew', 23)

    def test_netopt_roundtrip_runtime_values(self):
        self.run_shell('system', '''sysctl() {
 if [[ "$1" == -n ]]; then printf '777\\n'; else cp "$2" "$T/applied"; fi
}
_system_netopt_apply 1 || exit
_system_netopt_apply 2 || exit
_system_netopt_reset || exit
[[ ! -e "$T/etc/sysctl.d/99-fusionbox-netopt.conf" ]] || exit 8
[[ $(grep -c ' = 777' "$T/applied") == 11 ]]''')

    def test_netopt_missing_snapshot_refuses_reset(self):
        (self.root / 'etc/sysctl.d/99-fusionbox-netopt.conf').write_text('original')
        self.run_shell('system', '_system_netopt_reset', 1)
        self.assertEqual((self.root / 'etc/sysctl.d/99-fusionbox-netopt.conf').read_text(), 'original')

    def test_notify_mock_success_and_failure(self):
        setup = '''_notify_conf_get() { if [[ "$1" == TG_BOT_TOKEN ]]; then printf '123:dummy'; else printf 123; fi; }
curl() { printf '%s' '{"ok":true}'; }
_notify_send test || exit 1
curl() { printf '%s' '{"ok":false}'; }
_notify_send test'''
        self.run_shell('system', setup, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
