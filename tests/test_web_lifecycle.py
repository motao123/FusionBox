"""Web lifecycle tests (clone/cache/goaccess/upgrade/uninstall); nginx/mysql mocked."""
from test_safety import Safety


SITE_CONF = """server {{
    listen 80;
    server_name {src};
    root {root};
    index index.html;
}}
"""


class WebLifecycle(Safety):
    def setUp(self):
        super().setUp()
        self.src = 'old.test'
        self.siteroot = self.root / 'var/www/old.test'
        self.siteroot.mkdir(parents=True, exist_ok=True)
        (self.siteroot / 'index.html').write_text('<h1>old</h1>\n')
        avail = self.root / 'etc/nginx/sites-available'
        enabled = self.root / 'etc/nginx/sites-enabled'
        avail.mkdir(parents=True, exist_ok=True)
        enabled.mkdir(parents=True, exist_ok=True)
        conf = avail / f'{self.src}.conf'
        conf.write_text(SITE_CONF.format(src=self.src, root=self.siteroot))
        try:
            (enabled / f'{self.src}.conf').symlink_to(conf)
            self.have_symlink = True
        except OSError:
            (enabled / f'{self.src}.conf').write_text(conf.read_text())
            self.have_symlink = False

    def nginx_ok(self):
        return 'nginx() { if [[ "$1" == "-t" ]]; then return 0; fi; if [[ "$1" == "-s" ]]; then printf "nginx %s\\n" "$*" >> "$T/web"; return 0; fi; return 0; }\n'

    def cmd_nginx_ok(self):
        return 'command() { if [[ "$2" == nginx ]]; then return 0; fi; builtin command "$@"; }\n'

    def test_clone_copies_dir_and_generates_conf(self):
        body = self.nginx_ok() + 'confirm() { return 0; }\n' \
            'web_site_clone old.test new.test || exit 9'
        self.run_shell('web', body)
        self.assertTrue((self.root / 'var/www/new.test/index.html').exists())
        new_conf = (self.root / 'etc/nginx/sites-available' / 'new.test.conf'
                    if self.have_symlink else
                    self.root / 'etc/nginx/sites-enabled' / 'new.test.conf')
        text = new_conf.read_text()
        self.assertIn('server_name new.test;', text)
        self.assertNotIn('old.test', text)
        self.assertIn('web -s reload', (self.root / 'web').read_text()) if False else self.assertIn('nginx -s reload', (self.root / 'web').read_text())

    def test_clone_missing_source_refused(self):
        body = self.nginx_ok() + 'web_site_clone nope.test new.test || exit 9'
        self.run_shell('web', body, 9)

    def test_clone_rolls_back_on_nginx_test_failure(self):
        body = ('nginx() { if [[ "$1" == "-t" ]]; then return 1; fi; return 0; }\n'
                'confirm() { return 0; }\n'
                'web_site_clone old.test new.test || exit 9')
        self.run_shell('web', body, 9)
        self.assertFalse((self.root.parent / 'new.test').exists())
        self.assertFalse((self.root.parent / 'sites-available' / 'new.test.conf').exists())

    def test_clone_existing_target_refused(self):
        body = self.nginx_ok() + 'confirm() { return 0; }\n' \
            'mkdir -p "$T/var/www/taken.test"\n' \
            'web_site_clone old.test taken.test || exit 9'
        self.run_shell('web', body, 9)

    def test_cache_restarts_fpm_and_clears_cache_dir(self):
        cache_dir = self.root / 'cache'
        cache_dir.mkdir(exist_ok=True)
        (cache_dir / 'x').write_text('cache-data')
        nginx_conf = self.root / 'etc/nginx/nginx.conf'
        nginx_conf.parent.mkdir(parents=True, exist_ok=True)
        nginx_conf.write_text(f'fastcgi_cache_path {cache_dir} levels=1:2;\n')
        body = self.cmd_nginx_ok() + ('systemctl() { [[ "$1" == list-unit-files ]] && printf "php8.3-fpm.service php8.3-fpm enabled\\n" || '
                'printf "systemctl %s\\n" "$*" >> "$T/web"; }\n'
                'msg_ok() { printf "%s\\n" "$*" >> "$T/out"; }\n'
                'confirm() { return 0; }\n'
                'web_cache || exit 9')
        self.run_shell('web', body)
        web = (self.root / 'web').read_text()
        self.assertIn('systemctl restart php8.3-fpm.service', web)
        self.assertFalse(list(cache_dir.iterdir()))

    def test_cache_without_cf_skips_api(self):
        body = self.cmd_nginx_ok() + ('systemctl() { return 1; }\n'
                'curl() { printf "curl %s\\n" "$*" > "$T/cf"; return 0; }\n'
                'confirm() { return 0; }\n'
                'web_cache || exit 9')
        self.run_shell('web', body)
        self.assertFalse((self.root / 'cf').exists())

    def test_goaccess_requires_log(self):
        body = ('goaccess() { return 0; }\n'
                'command() { if [[ "$2" == goaccess ]]; then return 0; fi; builtin command "$@"; }\n'
                'web_goaccess || exit 9')
        self.run_shell('web', body, 9)

    def test_goaccess_generates_private_report(self):
        module = self.root / 'web.sh'
        module.write_text(module.read_text().replace('/root/fusionbox-reports', self.posix + '/reports'))
        logdir = self.root / 'var/log/nginx'
        logdir.mkdir(parents=True, exist_ok=True)
        (logdir / 'access.log').write_text('1.2.3.4 - - [01/Jan/2026:00:00:00 +0000] "GET / HTTP/1.1" 200 1 "-" "-"\n')
        body = ('goaccess() { touch "$3"; return 0; }\n'
                'command() { if [[ "$2" == goaccess ]]; then return 0; fi; builtin command "$@"; }\n'
                'web_goaccess || exit 9')
        self.run_shell('web', body)
        reports = list((self.root / 'reports').glob('goaccess-all-*.html'))
        self.assertEqual(len(reports), 1)

    def test_upgrade_rejects_unknown_component(self):
        body = self.cmd_nginx_ok() + 'web_upgrade printer'
        self.run_shell('web', body, 2)

    def test_upgrade_nginx_runs_only_upgrade(self):
        body = ('nginx() { [[ "$1" == "-v" ]] || [[ "$1" == -t ]]; return 0; }\n'
                'systemctl() { return 0; }\n'
                'confirm() { return 0; }\n'
                'apt-get() { printf "apt-get %s\\n" "$*" >> "$T/apt"; }\n'
                '_web_upgrade_pkgs_for() { printf nginx; }\n'
                'F_PKG_MGR=apt\n'
                'web_upgrade nginx || exit 9')
        self.run_shell('web', body)
        self.assertIn('apt-get install --only-upgrade -y nginx', (self.root / 'apt').read_text())

    def test_uninstall_gate_blocks_everything_without_yes(self):
        body = self.cmd_nginx_ok() + ('systemctl() { printf "systemctl %s\\n" "$*" >> "$T/s"; }\n'
                'apt-get() { printf "apt-get %s\\n" "$*" >> "$T/apt"; }\n'
                'rm() { printf "rm %s\\n" "$*" >> "$T/rm"; }\n'
                'confirm() { return 0; }\n'
                'dpkg() { return 1; }\n'
                'rpm() { return 1; }\n'
                'F_PKG_MGR=apt\n'
                'printf "not-yes\\n" | web_uninstall_lnmp')
        self.run_shell('web', body, 1)
        self.assertFalse((self.root / 'apt').exists())
        self.assertFalse((self.root / 'rm').exists())

    def test_uninstall_keeps_data_by_default(self):
        body = ('command() { if [[ "$2" == nginx || "$2" == mysql || "$2" == mariadb ]]; then return 0; fi; builtin command "$@"; }\n'
                'tar() { :; }\n'
                'systemctl() { :; }\n'
                'apt-get() { :; }\n'
                'dpkg() { return 1; }\n'
                'rpm() { return 1; }\n'
                'rm() { printf "rm %s\\n" "$*" >> "$T/rm"; }\n'
                'confirm() { return 0; }\n'
                'F_PKG_MGR=apt\n'
                'printf "YES\\nkeep\\n" | web_uninstall_lnmp || exit 9')
        self.run_shell('web', body)
        self.assertFalse((self.root / 'rm').exists())

    def test_uninstall_wipe_removes_data_dirs(self):
        body = ('command() { if [[ "$2" == nginx || "$2" == mysql || "$2" == mariadb ]]; then return 0; fi; builtin command "$@"; }\n'
                'nginx() { return 0; }\n'
                'tar() { :; }\n'
                'systemctl() { :; }\n'
                'apt-get() { :; }\n'
                'dpkg() { return 1; }\n'
                'rpm() { return 1; }\n'
                'rm() { printf "rm %s\\n" "$*" >> "$T/rm"; }\n'
                'confirm() { return 0; }\n'
                'F_PKG_MGR=apt\n'
                'printf "YES\\nwipe\\n" | web_uninstall_lnmp || exit 9')
        self.run_shell('web', body)
        rm = (self.root / 'rm').read_text()
        self.assertIn('/var/www', rm)
        self.assertIn('/var/lib/mysql', rm)


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
