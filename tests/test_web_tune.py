"""Web tune (G45/G48), brotli (G46) and wp-redis (G47) tests; nginx/php mocked."""
from test_safety import Safety


class WebTune(Safety):
    def nginx_conf(self, text='worker_connections 1024;\nhttp {\n}\n'):
        conf = self.root / 'etc/nginx/nginx.conf'
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text(text)
        return conf

    def mocks(self, nginx_t=0, php_t=0):
        return ('nginx() { if [[ "$1" == "-t" ]]; then return %d; fi; printf "nginx %%s\\n" "$*" >> "$T/web"; return 0; }\n'
                '_web_tune_php_bins() { printf php-fpm-mock; }\n'
                'php-fpm-mock() { if [[ "$1" == "-t" ]]; then return %d; fi; return 0; }\n'
                'systemctl() { if [[ "$1" == list-unit-files ]]; then return 0; fi; printf "systemctl %%s\\n" "$*" >> "$T/web"; return 0; }\n'
                ) % (nginx_t, php_t)

    def test_tune_high_updates_nginx_and_backs_up(self):
        conf = self.nginx_conf()
        body = self.mocks() + 'confirm() { return 0; }\n' \
            'FUSION_CONFIG_DIR="$T/fb"\n' \
            '_WEB_TUNE_BACKUP_BASE="$T/etc/fusionbox/tune-backups"\n' \
            'web_tune high || exit 9'
        self.run_shell('web', body)
        text = conf.read_text()
        self.assertIn('worker_connections 4096;', text)
        self.assertIn('gzip_vary', text)
        manifest = self.root / 'etc/fusionbox/tune-backups/latest/manifest'
        self.assertTrue(manifest.exists())
        self.assertIn('nginx.conf', manifest.read_text())

    def test_tune_standard_keeps_low_connections(self):
        conf = self.nginx_conf()
        body = self.mocks() + 'confirm() { return 0; }\n' \
            '_WEB_TUNE_BACKUP_BASE="$T/etc/fusionbox/tune-backups"\n' \
            'web_tune standard || exit 9'
        self.run_shell('web', body)
        self.assertIn('worker_connections 1024;', conf.read_text())
        self.assertNotIn('gzip_vary', conf.read_text())

    def test_tune_validation_failure_rolls_back(self):
        conf = self.nginx_conf()
        body = self.mocks(nginx_t=1) + 'confirm() { return 0; }\n' \
            '_WEB_TUNE_BACKUP_BASE="$T/etc/fusionbox/tune-backups"\n' \
            'web_tune high'
        self.run_shell('web', body, 1)
        self.assertIn('worker_connections 1024;', conf.read_text())

    def test_restore_recovers_backup(self):
        conf = self.nginx_conf()
        body = self.mocks() + 'confirm() { return 0; }\n' \
            '_WEB_TUNE_BACKUP_BASE="$T/etc/fusionbox/tune-backups"\n' \
            'web_tune high || exit 9\n' \
            'web_tune restore || exit 9'
        self.run_shell('web', body)
        self.assertIn('worker_connections 1024;', conf.read_text())

    def test_php_pool_scaled_by_mode(self):
        self.nginx_conf()
        pool = self.root / 'etc/php/8.3/fpm/pool.d/www.conf'
        pool.parent.mkdir(parents=True, exist_ok=True)
        pool.write_text('pm.max_children = 5\npm.start_servers = 2\npm.min_spare_servers = 1\npm.max_spare_servers = 3\n')
        meminfo = self.root / 'proc-meminfo'
        body = self.mocks() + 'confirm() { return 0; }\n' \
            '_WEB_TUNE_BACKUP_BASE="$T/etc/fusionbox/tune-backups"\n' \
            '_web_tune_total_mem_mb() { echo 4000; }\n' \
            'web_tune high || exit 9'
        self.run_shell('web', body)
        text = pool.read_text()
        self.assertIn('pm.max_children = 100', text)   # 4000/40
        self.assertIn('pm.max_spare_servers = 6', text)


class Brotli(Safety):
    def mocks(self, pkg_installed=1, nginx_t=0):
        return ('dpkg() { if [[ "$1 $2" == "-s libnginx-mod-http-brotli-filter" ]]; then return %d; fi; return 1; }\n'
                'nginx() { if [[ "$1" == "-t" ]]; then return %d; fi; printf "nginx %%s\\n" "$*" >> "$T/web"; return 0; }\n'
                '_install_pkg() { printf "pkg %%s\\n" "$*" >> "$T/pkg"; return 0; }\n'
                ) % (pkg_installed, nginx_t)

    def test_status_reports_uninstalled(self):
        body = self.mocks(pkg_installed=1) + 'msg() { printf "%s\\n" "$*" >> "$T/out"; }\nweb_brotli status'
        self.run_shell('web', body)
        out = (self.root / 'out').read_text()
        self.assertIn('未安装', out)
        self.assertIn('未启用', out)

    def test_on_installs_module_and_writes_conf(self):
        body = self.mocks(pkg_installed=1) + 'confirm() { return 0; }\n' \
            'mkdir -p "$T/etc/nginx/conf.d"\n' \
            'web_brotli on || exit 9'
        self.run_shell('web', body)
        pkg = (self.root / 'pkg').read_text()
        self.assertIn('libnginx-mod-http-brotli-filter', pkg)
        conf = self.root / 'etc/nginx/conf.d/fusionbox-brotli.conf'
        self.assertIn('brotli on;', conf.read_text())

    def test_on_validation_failure_removes_conf(self):
        body = self.mocks(nginx_t=1) + 'confirm() { return 0; }\n' \
            'mkdir -p "$T/etc/nginx/conf.d"\n' \
            'web_brotli on'
        self.run_shell('web', body, 1)
        self.assertFalse((self.root / 'etc/nginx/conf.d/fusionbox-brotli.conf').exists())

    def test_off_removes_owned_conf(self):
        conf = self.root / 'etc/nginx/conf.d/fusionbox-brotli.conf'
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text('brotli on;\n')
        body = self.mocks() + 'web_brotli off || exit 9'
        self.run_shell('web', body)
        self.assertFalse(conf.exists())


class WpRedis(Safety):
    def setUp(self):
        super().setUp()
        self.siteroot = self.root / 'var/www/site.test'
        self.siteroot.mkdir(parents=True, exist_ok=True)
        (self.siteroot / 'wp-config.php').write_text(
            "<?php\ndefine( 'DB_NAME', 'wp' );\n/* That's all, stop editing! Happy publishing. */\n")
        avail = self.root / 'etc/nginx/sites-available/site.test.conf'
        avail.parent.mkdir(parents=True, exist_ok=True)
        avail.write_text('server {\n listen 80;\n server_name site.test;\n root %s;\n}\n' % self.siteroot)
        enabled = self.root / 'etc/nginx/sites-enabled/site.test.conf'
        enabled.parent.mkdir(parents=True, exist_ok=True)
        enabled.write_text(avail.read_text())

    def mocks(self, php_l=0):
        return ('redis-cli() { printf PONG; }\n'
                'command() { if [[ "$2" == redis-cli || "$2" == php ]]; then return 0; fi; builtin command "$@"; }\n'
                'php() { if [[ "$1" == "-m" ]]; then printf "redis\\n"; return 0; fi; if [[ "$1" == "-l" ]]; then return %d; fi; return 0; }\n'
                '_install_pkg() { printf "pkg %%s\\n" "$*" >> "$T/pkg"; return 0; }\n'
                'confirm() { return 0; }\n'
                ) % (php_l,)

    def test_injects_redis_constants(self):
        body = self.mocks() + 'web_wp_redis site.test || exit 9'
        self.run_shell('web', body)
        text = (self.siteroot / 'wp-config.php').read_text()
        self.assertIn("define( 'WP_REDIS_HOST', '127.0.0.1' );", text)
        self.assertIn("define( 'WP_CACHE', true );", text)

    def test_injection_idempotent(self):
        body = self.mocks() + 'web_wp_redis site.test || exit 9\nweb_wp_redis site.test || exit 9'
        self.run_shell('web', body)
        text = (self.siteroot / 'wp-config.php').read_text()
        self.assertEqual(text.count('WP_REDIS_HOST'), 1)

    def test_php_lint_failure_rolls_back(self):
        body = self.mocks(php_l=1) + 'web_wp_redis site.test'
        self.run_shell('web', body, 1)
        text = (self.siteroot / 'wp-config.php').read_text()
        self.assertNotIn('WP_REDIS_HOST', text)

    def test_non_wp_site_refused(self):
        body = self.mocks() + 'web_wp_redis ghost.test || exit 9'
        self.run_shell('web', body, 9)


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
