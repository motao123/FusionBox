"""rsync tasks, file manager and small tools tests; rsync/scp mocked."""
import os
from test_safety import Safety


class RsyncTasks(Safety):
    def test_add_list_run_roundtrip(self):
        (self.root / 'data/src').mkdir(parents=True, exist_ok=True)
        (self.root / 'data/src/f.txt').write_text('hello')
        body = '''confirm() { return 0; }
_src=$T/data/src; _dst=$T/data/dst
mkdir -p "$_dst"
rsync() { printf "rsync %s
" "$*" >> "$T/rs"; return 0; }
mkdir -p "$T/etc/fusionbox"
printf 'demo|%s|%s|-a|no
' "$_src" "$_dst" >> "$T/etc/fusionbox/rsync-tasks.conf"
system_rsync run demo || exit 9
system_rsync list'''
        out = self.run_shell('system', body)
        self.assertIn('rsync -a', (self.root / 'rs').read_text())
        self.assertIn('demo', out)

    def test_endpoint_validation(self):
        body = '''_rsync_check_endpoint 'user@203.0.113.9:/backup' || exit 9
_rsync_check_endpoint '/absolute/path' || exit 9
_rsync_check_endpoint 'relative/path' || exit 9
_rsync_check_endpoint 'user@host bad' || exit 9'''
        self.run_shell('system', body, 9)

    def test_name_validation(self):
        body = '''_rsync_check_name 'bad name' || exit 9
_rsync_check_name 'ok-name_1' || exit 9'''
        self.run_shell('system', body, 9)


class FileManager(Safety):
    def redirect_trash(self):
        module = self.root / 'system.sh'
        module.write_text(module.read_text().replace('/root/.fusionbox_trash', self.posix + '/.fusionbox_trash'))

    def test_ls_cat_mkdir_chmod(self):
        if os.name == 'nt':
            self.skipTest('chmod/stat semantics differ on Windows')
        self.redirect_trash()
        d = self.root / 'work'
        d.mkdir(exist_ok=True)
        (d / 'a.txt').write_text('content')
        body = '''system_file mkdir "$T/work/sub" || exit 9
[ -d "$T/work/sub" ] || exit 9
system_file chmod 700 "$T/work/a.txt" || exit 9
[ "$(stat -c %a "$T/work/a.txt")" = 700 ] || exit 9
system_file ls "$T/work" || exit 9
system_file cat "$T/work/a.txt" || exit 9'''
        out = self.run_shell('system', body)
        self.assertIn('content', out)

    def test_del_goes_to_trash_not_gone(self):
        self.redirect_trash()
        d = self.root / 'work'
        d.mkdir(exist_ok=True)
        (d / 'victim.txt').write_text('precious')
        body = 'system_file del "$T/work/victim.txt" || exit 9'
        self.run_shell('system', body)
        self.assertFalse((d / 'victim.txt').exists())
        trash = list((self.root / '.fusionbox_trash/files').glob('victim.txt_*'))
        self.assertEqual(len(trash), 1)
        self.assertEqual(trash[0].read_text(), 'precious')

    def test_del_root_refused(self):
        body = "system_file del /"
        self.run_shell('system', body, 1)

    def test_tar_roundtrip(self):
        d = self.root / 'work'
        d.mkdir(exist_ok=True)
        (d / 'a.txt').write_text('x')
        body = '''system_file tar "$T/work" "$T/work.tar.gz" || exit 9
mkdir -p "$T/out"
system_file untar "$T/work.tar.gz" "$T/out" || exit 9'''
        self.run_shell('system', body)
        self.assertTrue((self.root / 'out/work/a.txt').exists())

    def test_send_validates_remote_format(self):
        d = self.root / 'work'
        d.mkdir(exist_ok=True)
        (d / 'a.txt').write_text('x')
        body = "system_file send \"$T/work/a.txt\" 'no-colon-target'"
        self.run_shell('system', body, 2)


class SmallTools(Safety):
    def test_genpass_length(self):
        body = ('msg() { printf "%s\\n" "$*"; }\n'
                '_genpass_raw() { printf "abcdefghij0123456789ABCDEFGH"; }\n'
                'pw=$(system_genpass 24); echo "LEN=${#pw}"')
        out = self.run_shell('system', body)
        self.assertIn('LEN=24', out)

    def test_genpass_rejects_bad_length(self):
        self.run_shell('system', 'system_genpass 4 || exit 9', 9)

    def test_gai_v4_first_and_default(self):
        gai = self.root / 'etc/gai.conf'
        gai.parent.mkdir(parents=True, exist_ok=True)
        gai.write_text('# default\n')
        body = '''msg() { printf "%s\n" "$*" >> "$T/out"; }
system_gai v4-first || exit 9
system_gai status || exit 9
system_gai default || exit 9
system_gai status || exit 9'''
        self.run_shell('system', body)
        out = (self.root / 'out').read_text()
        self.assertIn('IPv4 优先', out)
        self.assertIn('IPv6 优先', out)
        self.assertNotIn('FusionBox: prefer IPv4', gai.read_text())


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
