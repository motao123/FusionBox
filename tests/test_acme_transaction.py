"""ACME transaction tests; intentionally ignored by git."""
from test_safety import Safety


class AcmeTransaction(Safety):
    def setUp(self):
        super().setUp()
        self.nginx = self.root / 'etc/nginx'
        (self.nginx / 'conf.d').mkdir(parents=True, exist_ok=True)
        (self.nginx / 'sites-enabled').mkdir(parents=True, exist_ok=True)
        self.le = self.root / 'etc/letsencrypt'
        (self.le / 'live').mkdir(parents=True, exist_ok=True)

    @staticmethod
    def command_mock():
        return 'command() { case "$2" in nginx|certbot|openssl|flock) return 0;; esac; builtin command "$@"; }\n'

    @staticmethod
    def certbot_ok():
        return 'certbot() { case "$1" in --version) printf "certbot 2.10.0\\n";; plugins) printf "* webroot\\n";; *) return 0;; esac; }\n'

    def test_strict_inputs_rejected(self):
        body = ('web_ssl_preflight --domain bad..example.com; [[ $? == 2 ]] || exit 8\n'
                'web_ssl_issue --domain example.com; [[ $? == 2 ]] || exit 9\n'
                'web_ssl_renew --days 0; [[ $? == 2 ]] || exit 10')
        self.run_shell('web', body)

    def test_webroot_rejects_unsafe_chars_and_symlink_ancestor(self):
        real = self.root / 'real-root'
        real.mkdir()
        link = self.root / 'linked-root'
        try:
            link.symlink_to(real, target_is_directory=True)
        except OSError:
            self.skipTest('symlink privilege unavailable')
        body = ('_web_acme_path_valid "/tmp/root with-space" && exit 8\n'
                '_web_acme_path_valid "$T/linked-root/site" && exit 9\n'
                '_web_acme_path_valid "$T/real-root" || exit 10')
        self.run_shell('web', body)

    def test_fixed_config_refuses_foreign_or_drifted_owner(self):
        target = self.nginx / 'conf.d/fusionbox-acme-example.com.conf'
        target.write_text('# external config\n')
        root = self.root / 'var/www/example.com'
        body = f'_web_acme_write_challenge example.com "{root.as_posix()}" "{target.as_posix()}"'
        self.run_shell('web', body, 1)
        target.write_text('# Managed by FusionBox ACME transaction: challenge\n# Owner-State-SHA256: deadbeef\n')
        self.run_shell('web', body, 1)

    def test_tls_config_keeps_owner_marker_and_hash(self):
        target = self.nginx / 'conf.d/fusionbox-tls-example.com.conf'
        root = self.root / 'var/www/example.com'
        root.mkdir(parents=True)
        body = f'_web_acme_write_tls example.com "{root.as_posix()}" "" /cert.pem /key.pem "{target.as_posix()}"'
        self.run_shell('web', body)
        lines = target.read_text().splitlines()
        self.assertEqual(lines[0], '# Managed by FusionBox ACME transaction: tls')
        self.assertRegex(lines[1], r'^# Owner-State-SHA256: [0-9a-f]{64}$')

    def test_failure_after_challenge_enable_uses_trap_rollback(self):
        body = self.command_mock() + '''nginx() { return 0; }
systemctl() { printf "reload\\n" >> "$T/reloads"; return 0; }
getent() { return 2; }
certbot() { case "$1" in --version) printf "certbot 2.10.0\\n";; plugins) printf "* webroot\\n";; *) return 23;; esac; }
WEB_ACME_HTTP_PORT=18080 WEB_ACME_HTTPS_PORT=18443
web_ssl_issue --domain example.com --email admin@example.com'''
        self.run_shell('web', body, 23)
        self.assertFalse((self.nginx / 'conf.d/fusionbox-acme-example.com.conf').exists())
        self.assertGreaterEqual((self.root / 'reloads').read_text().count('reload'), 2)

    def test_preflight_dns_is_report_only(self):
        site = self.nginx / 'sites-enabled/example.com.conf'
        root = self.root / 'var/www/example.com'
        root.mkdir(parents=True)
        site.write_text(f'server {{\n listen 18080;\n server_name example.com;\n root {root.as_posix()};\n}}\n')
        body = self.command_mock() + self.certbot_ok() + '''nginx() { return 0; }
getent() { return 2; }
WEB_ACME_HTTP_PORT=18080 WEB_ACME_HTTPS_PORT=18443
web_ssl_preflight --domain example.com || exit 9'''
        self.run_shell('web', body)

    def test_issue_failure_removes_temporary_site(self):
        body = self.command_mock() + '''nginx() { return 0; }
systemctl() { return 0; }
getent() { return 2; }
certbot() { case "$1" in --version) printf "certbot 2.10.0\\n";; plugins) printf "* webroot\\n";; *) return 23;; esac; }
WEB_ACME_HTTP_PORT=18080 WEB_ACME_HTTPS_PORT=18443
web_ssl_issue --domain example.com --email admin@example.com'''
        self.run_shell('web', body, 23)
        self.assertFalse((self.nginx / 'conf.d/fusionbox-acme-example.com.conf').exists())

    def test_renew_unchanged_does_not_reload(self):
        body = self.command_mock() + self.certbot_ok() + '''mkdir -p "$T/etc/letsencrypt/live/example.com" "$T/var/lib/fusionbox/acme"
touch "$T/etc/letsencrypt/live/example.com/fullchain.pem"
_web_cert_days() { printf "5\\n"; }
_web_acme_fingerprints() { printf "same\\n"; }
flock() { return 0; }
systemctl() { touch "$T/reloaded"; }
web_ssl_renew --days 30 || exit 9'''
        self.run_shell('web', body)
        self.assertFalse((self.root / 'reloaded').exists())


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
