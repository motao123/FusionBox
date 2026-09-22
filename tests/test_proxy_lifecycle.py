"""Isolated proxy lifecycle tests; downloads, services and installers are mocked."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProxyLifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fusionbox-proxy-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.posix = self.root.as_posix()
        if os.name == "nt":
            self.posix = "/" + self.posix[0].lower() + self.posix[2:]
        source = (ROOT / "src/modules/proxy.sh").read_text(encoding="utf-8")
        for prefix in ("/etc/", "/usr/local/", "/var/"):
            source = source.replace(prefix, self.posix + prefix)
        (self.root / "proxy.sh").write_text(source, encoding="utf-8")

    def run_shell(self, body, expected=0, real_links=False):
        # 模块文案已走语言包（v1.43.0）：先初始化 i18n，否则 $(L KEY) 取空；
        # 这些用例用 confirm 的提示语内容决定回答（*233boy*），空提示会把行为带偏。
        i18n_prelude = ('FUSION_I18N_DIR="%s/src/i18n"\n'
                        'source "%s/src/lib/i18n.sh"\n'
                        '_i18n_init >/dev/null 2>&1 || true\n') % (ROOT.as_posix(), ROOT.as_posix())
        script = i18n_prelude + '''source "$T/proxy.sh"
for name in msg msg_info msg_warn msg_err msg_title msg_ok _log_write pause _require_root; do
  eval "$name() { :; }"
done
confirm() { printf '%s\n' "$*" >> "$T/prompts"; return 0; }
systemctl() { printf '%s\n' "$*" >> "$T/services"; return 0; }
_download() { touch "$T/download"; return 99; }
curl() { return 98; }
wget() { return 98; }
mkdir -p "$(dirname "$SB_SH_BIN")" "$P_SERVICE_DIR"
native() {
  mkdir -p "$P_BIN_DIR" "$P_CONF_DIR"
  printf 'sing-box\n' > "$P_BASE_DIR/current_backend"
  printf '#!/bin/bash\nexit 88\n' > "$P_BIN_DIR/sing-box"
  chmod +x "$P_BIN_DIR/sing-box"
  printf 'ExecStart=%s/sing-box run -c %s/config.json\n' "$P_BIN_DIR" "$P_CONF_DIR" > "$P_SERVICE_DIR/fusionbox-proxy.service"
}
upstream() {
  mkdir -p "$SB_CORE_DIR/sh" "$SB_CORE_DIR/conf"
  printf '#!/bin/bash\nprintf "%%s\n" "$*" >> "$T/upstream"\nexit "${UPSTREAM_RC:-0}"\n' > "$SB_CORE_DIR/sh/sing-box.sh"
  chmod +x "$SB_CORE_DIR/sh/sing-box.sh"
  link "$SB_CORE_DIR/sh/sing-box.sh" "$SB_SH_BIN"
}
link() {
  ln -s "$1" "$2" || exit 77
  [[ -L "$2" ]] || exit 77
}
'''
        if os.name == "nt" and not real_links:
            # Mock only link identity when Windows lacks symlink privileges.
            script += '''
declare -A mock_links=()
link() {
  cp "$1" "$2" || exit 76
  mock_links["$2"]="$1"
}
_proxy_link_points_to() {
  [[ -n "${mock_links[$1]:-}" && "${mock_links[$1]}" == "$2" ]]
}
'''
        script += body
        env = os.environ.copy()
        env["T"] = self.posix
        # Git Bash otherwise silently copies instead of creating symlinks.
        env["MSYS"] = env.get("MSYS", "") + " winsymlinks:nativestrict"
        result = subprocess.run(["bash"], input=script, text=True,
                                capture_output=True, env=env, timeout=20)
        if result.returncode == 77:
            self.skipTest("Native symlink privilege unavailable; run these cases on Linux")
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def exists(self, path):
        return (self.root / path).exists()

    def test_upstream_only_uninstall(self):
        self.run_shell('upstream; proxy_uninstall')
        self.assertEqual((self.root / "upstream").read_text().strip(), "uninstall")
        self.assertFalse(self.exists("services"))
        self.assertEqual(len((self.root / "prompts").read_text().splitlines()), 1)

    def test_native_only_removes_owned_link(self):
        self.run_shell('native; link "$P_BIN_DIR/sing-box" "$SB_SH_BIN"; proxy_uninstall')
        self.assertFalse(self.exists("etc/fusionbox/proxy"))
        self.assertFalse((self.root / "usr/local/bin/sing-box").is_symlink())
        self.assertFalse(self.exists("upstream"))

    def test_coexistence_preserves_upstream_when_declined(self):
        self.run_shell('''native; upstream
confirm() { [[ "$*" != *233boy* ]]; }
proxy_uninstall
_singbox_233_installed''')
        self.assertFalse(self.exists("etc/fusionbox/proxy"))
        self.assertFalse(self.exists("upstream"))

    def test_coexistence_uninstalls_both(self):
        self.run_shell('native; upstream; proxy_uninstall')
        self.assertTrue(self.exists("upstream"))
        self.assertFalse(self.exists("etc/fusionbox/proxy"))

    def test_declining_native_can_still_uninstall_upstream(self):
        self.run_shell('''native; upstream
confirm() { [[ "$*" == *233boy* ]]; }
proxy_uninstall''')
        self.assertTrue(self.exists("etc/fusionbox/proxy"))
        self.assertTrue(self.exists("upstream"))
        self.assertFalse(self.exists("services"))

    def test_legacy_link_with_upstream_directory_not_executed(self):
        self.run_shell('''native; mkdir -p "$SB_CORE_DIR/sh"
link "$P_BIN_DIR/sing-box" "$SB_SH_BIN"
proxy_uninstall''')
        self.assertFalse(self.exists("upstream"))
        self.assertTrue(self.exists("etc/sing-box/sh"))

    def test_unknown_command_and_service_preserved(self):
        self.run_shell('''native; mkdir -p "$SB_CORE_DIR/sh"
printf '#!/bin/bash\nexit 88\n' > "$SB_SH_BIN"
chmod +x "$SB_SH_BIN"
printf 'unrelated\n' > "$P_SERVICE_DIR/fusionbox-proxy.service"
proxy_uninstall''')
        self.assertTrue(self.exists("usr/local/bin/sing-box"))
        self.assertTrue(self.exists("etc/systemd/system/fusionbox-proxy.service"))
        self.assertTrue(self.exists("etc/sing-box/sh"))
        self.assertFalse(self.exists("services"))

    def test_install_refuses_occupied_namespaces(self):
        for path in ("usr/local/bin/sing-box", "usr/local/bin/sb",
                     "etc/sing-box", "etc/systemd/system/sing-box.service",
                     "var/log/sing-box"):
            with self.subTest(path=path):
                target = self.root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("unrelated")
                self.run_shell('proxy_sb', 1)
                self.assertEqual(target.read_text(), "unrelated")
                self.assertFalse(self.exists("download"))
                target.unlink()

    def test_install_refuses_legacy_native_link(self):
        self.run_shell('native; link "$P_BIN_DIR/sing-box" "$SB_SH_BIN"; proxy_sb', 1)
        self.assertFalse(self.exists("download"))
        self.assertTrue(self.exists("etc/fusionbox/proxy/bin/sing-box"))

    def test_no_confirmation_no_install(self):
        self.run_shell('confirm() { return 1; }; proxy_sb', 1)
        self.assertFalse(self.exists("download"))

    def test_download_failure_code(self):
        self.run_shell('proxy_sb', 99)

    def test_installer_failure_code(self):
        self.run_shell('_download() { printf "exit 37\n" > "$2"; }; proxy_sb', 37)

    def test_installer_success_without_manager_fails(self):
        self.run_shell('_download() { printf "exit 0\n" > "$2"; }; proxy_sb', 1)

    def test_manager_failure_code(self):
        self.run_shell('upstream; export UPSTREAM_RC=42; proxy_sb status', 42)

    def test_uninstaller_failure_code(self):
        self.run_shell('upstream; export UPSTREAM_RC=43; proxy_uninstall', 43)

    def test_native_service_failure_keeps_files(self):
        self.run_shell('native; systemctl() { return 44; }; proxy_uninstall', 44)
        self.assertTrue(self.exists("etc/fusionbox/proxy/bin/sing-box"))

    def test_native_declined(self):
        self.run_shell('native; confirm() { return 1; }; proxy_uninstall')
        self.assertTrue(self.exists("etc/fusionbox/proxy/bin/sing-box"))
        self.assertFalse(self.exists("services"))

    def test_native_install_preserves_unknown_command(self):
        self.run_shell('''printf unrelated > "$(dirname "$SB_SH_BIN")/xray"
proxy_install <<< 1''', 1)
        self.assertEqual((self.root / "usr/local/bin/xray").read_text(), "unrelated")
        self.assertFalse(self.exists("download"))
        self.assertFalse(self.exists("etc/fusionbox/proxy"))


    def test_real_link_ownership(self):
        self.run_shell('''native
link "$P_BIN_DIR/sing-box" "$SB_SH_BIN"
_proxy_link_points_to "$SB_SH_BIN" "$P_BIN_DIR/sing-box" || exit 2
_singbox_233_installed && exit 3
rm "$P_BIN_DIR/sing-box"
_proxy_link_points_to "$SB_SH_BIN" "$P_BIN_DIR/sing-box"''', real_links=True)

    def test_real_upstream_link(self):
        self.run_shell('upstream; _singbox_233_installed', real_links=True)

    def test_upstream_declined(self):
        self.run_shell('upstream; confirm() { return 1; }; proxy_uninstall')
        self.assertFalse(self.exists("upstream"))
        self.assertFalse(self.exists("services"))

    def test_unknown_command_without_native_not_executed(self):
        self.run_shell('''mkdir -p "$SB_CORE_DIR/sh"
printf '#!/bin/bash\nexit 88\n' > "$SB_SH_BIN"
chmod +x "$SB_SH_BIN"
proxy_uninstall''')
        self.assertTrue(self.exists("usr/local/bin/sing-box"))
        self.assertFalse(self.exists("prompts"))

    def test_install_menu_preserves_failure_code(self):
        self.run_shell('_download() { printf "exit 38\n" > "$2"; }; proxy_install <<< 3', 38)

    def test_mock_install_success(self):
        self.run_shell('''_download() { printf 'exit 0\n' > "$2"; }
bash() { upstream; }
proxy_sb
_singbox_233_installed''')
        self.assertFalse(self.exists("etc/fusionbox/proxy"))
        self.assertFalse(self.exists("upstream"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
