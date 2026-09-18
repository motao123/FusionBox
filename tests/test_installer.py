"""Installer tests with temp paths and stub downloads; no system writes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def shellpath(path):
    text = path.as_posix()
    return '/' + text[0].lower() + text[2:] if os.name == 'nt' else text


class Installer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fusionbox-install-')
        self.root = Path(self.tmp.name)
        self.release = self.root / 'release'
        self.base = self.root / 'installed'
        self.base.mkdir()
        self.release.mkdir()
        for name in ('src', 'templates', 'configs'):
            shutil.copytree(ROOT / name, self.release / name)
        for name in ('fusion.sh', 'install.sh', 'version.txt'):
            shutil.copy2(ROOT / name, self.release / name)
        (self.root / 'home').mkdir()
        (self.root / 'bin').mkdir()
        self.t = shellpath(self.root)
        self.helper = shellpath(ROOT / 'src/lib/deploy.sh')
        self.script = (ROOT / 'install.sh').read_text(encoding='utf-8')
        self.script = self.script.replace('FUSION_BASE="/etc/fusionbox"', f'FUSION_BASE="{self.t}/installed"')
        self.script = self.script.replace('FUSION_BIN="/usr/local/bin/fusionbox"', f'FUSION_BIN="{self.t}/bin/fusionbox"')
        self.script = self.script.replace('[[ $EUID -ne 0 ]]', '[[ 0 -ne 0 ]]')
        (self.release / 'install.sh').write_text(self.script, encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def run_bash(self, body, success=True):
        env = os.environ.copy()
        env['HOME'] = self.t + '/home'
        # MSYS otherwise emulates symlinks by copying the target, which need not
        # exist yet. Linux runs the real ln; Windows tests command activation via a stub.
        if os.name == 'nt':
            body = 'ln() { printf "%s\n" "$3" > "$4"; }; export -f ln\n' + body
        result = subprocess.run(['bash'], input=f'T="{self.t}"\n' + body,
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def old_install(self):
        shutil.copytree(self.release, self.base, dirs_exist_ok=True)
        (self.base / 'version.txt').write_text('0.0.1\n')
        (self.base / 'fusion.sh').write_text('#!/bin/bash\nprintf old\n')
        (self.base / 'configs/config.yaml').write_text('custom config\n')
        (self.base / 'proxy').mkdir()
        (self.base / 'proxy/secret').write_text('credential\n')
        (self.base / 'proxy/secret').chmod(0o600)
        (self.base / '.user-state').write_text('hidden\n')
        (self.root / 'bin/fusionbox').write_text('old command\n')

    def snapshot(self):
        return {str(p.relative_to(self.base)): (p.read_bytes(), p.stat().st_mode)
                for p in self.base.rglob('*') if p.is_file()}

    def deploy(self, stub='', success=True, bin=False):
        return self.run_bash(f'source "{self.helper}"\n{stub}\n'
                             'fusion_deploy "$T/release" "$T/installed"' +
                             (' "$T/bin/fusionbox"' if bin else ''), success)

    def test_fresh_install(self):
        self.deploy()
        self.assertEqual((self.base / 'version.txt').read_bytes(), (self.release / 'version.txt').read_bytes())

    def test_update_preserves_state_and_removes_stale_code(self):
        self.old_install()
        (self.base / 'src/obsolete.sh').write_text('old')
        mode = (self.base / 'proxy/secret').stat().st_mode
        self.deploy()
        self.assertFalse((self.base / 'src/obsolete.sh').exists())
        self.assertEqual((self.base / 'configs/config.yaml').read_text(), 'custom config\n')
        self.assertEqual((self.base / 'proxy/secret').read_text(), 'credential\n')
        self.assertEqual((self.base / 'proxy/secret').stat().st_mode, mode)
        self.assertEqual((self.base / '.user-state').read_text(), 'hidden\n')
        self.assertTrue(list(self.base.glob('.fusionbox-backup.*/old/fusion.sh')))

    def test_partial_copy_failure_preserves_old_tree(self):
        self.old_install()
        before = self.snapshot()
        self.deploy('cp() { command cp "$@"; return 19; }', False)
        self.assertEqual(self.snapshot(), before)

    def test_activation_failure_rolls_back(self):
        self.old_install()
        before = self.snapshot()
        self.deploy('mv() { [[ "$3" != */new/fusion.sh ]] || return 23; command mv "$@"; }', False)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_payload_preserves_old_tree(self):
        self.old_install()
        before = self.snapshot()
        (self.release / 'src/init.sh').write_text('if then\n')
        self.deploy(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_command_directory_is_not_modified(self):
        (self.root / 'bin/fusionbox').mkdir()
        self.deploy(success=False, bin=True)
        self.assertFalse((self.base / 'fusion.sh').exists())

    def test_managed_symlink_refused(self):
        try:
            (self.base / 'src').symlink_to(self.release / 'src', target_is_directory=True)
        except OSError:
            self.skipTest('Native symlink privileges unavailable')
        self.deploy(success=False)
        self.assertTrue((self.base / 'src').is_symlink())


    def test_entry_forms(self):
        for entry in ('checkout', 'standalone', 'process', 'stdin'):
            with self.subTest(entry=entry):
                shutil.rmtree(self.base)
                self.base.mkdir()
                (self.root / 'bin/fusionbox').unlink(missing_ok=True)
                (self.root / 'standalone.sh').write_text(self.script, encoding='utf-8')
                prelude = '''curl() {
  if [[ "$1" == -s ]]; then return 0; fi
  command cp "$T/package.tar.gz" "${@: -1}"
}
export -f curl
export T
tar czf "$T/package.tar.gz" -C "$T" --transform='s,^release,FusionBox-main,' release || exit
'''
                command = {'checkout': 'bash "$T/release/install.sh"',
                           'standalone': 'bash "$T/standalone.sh"',
                           'process': 'bash <(command cat "$T/standalone.sh")',
                           'stdin': 'bash -s < "$T/standalone.sh"'}[entry]
                self.run_bash(prelude + command)
                self.assertTrue((self.base / 'src/lib/deploy.sh').exists())

    def test_offline_checkout(self):
        self.run_bash('curl() { return 1; }; export -f curl\nbash "$T/release/install.sh"')
        self.assertTrue((self.base / 'fusion.sh').exists())

    def test_self_update(self):
        self.old_install()
        text = (ROOT / 'fusion.sh').read_text(encoding='utf-8')
        function = text.split('self_update() (', 1)[1].split('\n)\n', 1)[0]
        self.run_bash('self_update() (' + function + '\n)\n' + '''
msg_info() { :; }; msg_ok() { :; }
FUSION_BASE="$T/installed"; FUSION_VER=0.0.1
_download() {
  if [[ "$1" == */version.txt ]]; then command cp "$T/release/version.txt" "$2"
  else command cp "$T/package.tar.gz" "$2"; fi
}
tar czf "$T/package.tar.gz" -C "$T" --transform='s,^release,FusionBox-main,' release || exit
self_update
''')
        self.assertEqual((self.base / 'version.txt').read_bytes(), (self.release / 'version.txt').read_bytes())
        self.assertEqual((self.base / 'proxy/secret').read_text(), 'credential\n')


    def test_command_activation_failure_rolls_back(self):
        self.old_install()
        before = self.snapshot()
        (self.root / 'bin/fusionbox').unlink()
        self.deploy('mv() { [[ "$3" != */.fusionbox-bin.*/new ]] || return 23; command mv "$@"; }', False, True)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.root / 'bin/fusionbox').exists())
        self.assertFalse((self.root / 'home/.config/fusionbox/config.yaml').exists())

    def test_fresh_activation_failure_leaves_no_partial_code(self):
        self.deploy('mv() { [[ "$3" != */new/fusion.sh ]] || return 23; command mv "$@"; }', False)
        self.assertEqual(list(self.base.iterdir()), [])

    def test_lock_refuses_concurrent_deployment(self):
        (self.base / '.fusionbox-install.lock').mkdir()
        self.deploy(success=False)
        self.assertFalse((self.base / 'fusion.sh').exists())

    def test_existing_user_config_preserved(self):
        config = self.root / 'home/.config/fusionbox/config.yaml'
        config.parent.mkdir(parents=True)
        config.write_text('private config')
        self.deploy(bin=True)
        self.assertEqual(config.read_text(), 'private config')

    def test_in_place_install(self):
        self.old_install()
        # A current installed checkout can be its own offline source.
        shutil.copy2(self.release / 'fusion.sh', self.base / 'fusion.sh')
        self.run_bash(f'source "{self.helper}"\nfusion_deploy "$T/installed" "$T/installed"')
        self.assertEqual((self.base / 'proxy/secret').read_text(), 'credential\n')


    def test_unrelated_command_preserved(self):
        self.old_install()
        before = self.snapshot()
        self.deploy(success=False, bin=True)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'bin/fusionbox').read_text(), 'old command\n')

    def test_owned_link_preserved_on_success_and_failure(self):
        self.old_install()
        command = self.root / 'bin/fusionbox'
        command.unlink()
        try:
            command.symlink_to('../installed/fusion.sh')
        except OSError:
            self.skipTest('Native symlink privileges unavailable')
        self.deploy(bin=True)
        self.assertEqual(os.readlink(command), '../installed/fusion.sh')
        before = self.snapshot()
        self.deploy('mv() { [[ "$3" != */new/fusion.sh ]] || return 23; command mv "$@"; }', False, True)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(os.readlink(command), '../installed/fusion.sh')

    def test_unrelated_dangling_link_preserved(self):
        command = self.root / 'bin/fusionbox'
        try:
            command.symlink_to('../missing-unrelated')
        except OSError:
            self.skipTest('Native symlink privileges unavailable')
        self.deploy(success=False, bin=True)
        self.assertEqual(os.readlink(command), '../missing-unrelated')

    @unittest.skipIf(os.name == 'nt', 'POSIX permission semantics require Linux')
    def test_private_config_and_transaction_modes(self):
        self.old_install()
        (self.root / 'bin/fusionbox').unlink()
        self.deploy(bin=True)
        config = self.root / 'home/.config/fusionbox/config.yaml'
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        for backup in self.base.glob('.fusionbox-backup.*'):
            self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
            self.assertEqual((backup / 'old').stat().st_mode & 0o777, 0o700)


if __name__ == '__main__':
    unittest.main(verbosity=2)
