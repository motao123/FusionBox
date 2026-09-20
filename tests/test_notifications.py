"""Generated cron execution with redirected paths and mocked external actions."""
import os
from pathlib import Path
import subprocess
import unittest
from test_safety import Safety


class Notifications(Safety):
    def prepare(self, name, installer):
        for directory in ('etc/cron.d', 'var/lib/fusionbox', 'var/log', 'proc/net'):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        module = self.root / (name + '.sh')
        module.write_text(module.read_text(encoding='utf-8').replace('/proc/', self.posix + '/proc/'), encoding='utf-8')
        self.run_shell(name, installer)

    def execute(self, name, mock, expected=0):
        body = 'flock() { return 0; }; sleep() { :; }; wall() { :; }; shutdown() { return 99; };\n'
        body += mock + '\nsource "$T/usr/local/bin/' + name + '"'
        return self.run_shell('system', body, expected)

    def notify_config(self):
        (self.root / 'etc/fusionbox/notify.conf').write_text('TG_BOT_TOKEN=123:dummy\nTG_CHAT_ID=123\nALERT_CPU=0\nALERT_MEM=0\nALERT_DISK=0\nCOOLDOWN_MIN=30\n')

    def test_transport_semantics_and_no_token_argv(self):
        for response, expected in (('{"ok": true}', 0), ('{"ok":false,"description":"ok:true"}', 1), ('not-json', 1), ('{"ok":"true"}', 1)):
            self.run_shell('system', '''curl() {
[[ "$*" != *123:dummy* ]] || exit 88
read -r config
[[ "$config" == *123:dummy* ]] || exit 89
printf '%s' ''' + "'" + response + "'" + '''
}
_fb_telegram_send 123:dummy 123 message''', expected)

    def test_notify_failed_send_retries_then_cooldown(self):
        self.prepare('system', '_notify_install_check')
        self.notify_config()
        (self.root / 'proc/stat').write_text('cpu 1 1 1 1 1 1 1\n')
        (self.root / 'proc/meminfo').write_text('MemTotal: 100\nMemAvailable: 1\n')
        state = self.root / 'var/lib/fusionbox/notify.state'
        self.execute('fusionbox-notify-check', 'curl() { printf \'{"ok":false}\'; }', 1)
        self.assertFalse(state.exists())
        self.execute('fusionbox-notify-check', 'curl() { [[ "$*" != *123:dummy* ]] || return 88; printf \'{"ok": true}\'; }')
        before = state.read_text()
        self.execute('fusionbox-notify-check', 'curl() { touch "$T/unexpected"; return 1; }')
        self.assertFalse((self.root / 'unexpected').exists())
        self.assertEqual(state.read_text(), before)

    def test_traffic_failure_retry_and_shutdown_mock(self):
        self.prepare('system', '_traffic_guard_install_bin')
        self.notify_config()
        (self.root / 'proc/net/dev').write_text('eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n')
        (self.root / 'etc/fusionbox/traffic-guard.conf').write_text('LIMIT_GB=1\nACTION=shutdown\n')
        state = self.root / 'var/lib/fusionbox/traffic-guard.state'
        import datetime
        month = datetime.datetime.now().strftime('%Y-%m')
        def reset():
            state.write_text(f'MONTH={month}\nLAST_RUN=0\nBASE_RX=0\nBASE_TX=0\nTOTAL=2147483648\n')
        flag = self.root / 'var/lib/fusionbox/traffic-guard.shutdown'
        reset()
        self.execute('fusionbox-traffic-guard', 'curl() { printf \'{"ok":false}\'; }; shutdown() { touch "$T/unexpected"; }', 1)
        self.assertFalse(flag.exists()); self.assertFalse((self.root / 'unexpected').exists())
        reset()
        self.execute('fusionbox-traffic-guard', 'curl() { printf \'{"ok":true}\'; }; shutdown() { return 23; }', 1)
        self.assertFalse(flag.exists())
        reset()
        self.execute('fusionbox-traffic-guard', 'curl() { printf \'{"ok":true}\'; }; shutdown() { touch "$T/mock-shutdown"; }')
        self.assertTrue(flag.exists()); self.assertTrue((self.root / 'mock-shutdown').exists())

    def test_cf_zone_switch_and_failure(self):
        self.prepare('web', '_web_guard_cf_adaptive <<< 1')
        (self.root / 'proc/loadavg').write_text('9 0 0\n')
        config = self.root / 'etc/fusionbox/cloudflare.conf'
        def zone(value):
            config.write_text(f'CF_API_TOKEN=dummy_token\nCF_ZONE_ID={value * 32}\nLOAD_THRESHOLD=5\n')
        mock = '''curl() { if [[ "$*" == *PATCH* ]]; then printf '{"success": true}'; else printf '{"success":true,"result":{"value":"medium"}}'; fi; }'''
        zone('a'); self.execute('fusionbox-cf-guard', mock)
        zone('b'); self.execute('fusionbox-cf-guard', mock)
        for value in ('a', 'b'):
            state = self.root / ('var/lib/fusionbox/cf-guard.' + value * 32 + '.state')
            self.assertEqual(state.read_text().strip(), 'under_attack')
            self.assertEqual(Path(str(state) + '.original').read_text().strip(), 'medium')
        zone('c')
        self.execute('fusionbox-cf-guard', mock.replace('{"success": true}', '{"success": false}'), 1)
        self.assertFalse((self.root / ('var/lib/fusionbox/cf-guard.' + 'c' * 32 + '.state')).exists())
        self.run_shell('web', '_web_guard_cf_adaptive <<< 2')
        self.assertTrue((self.root / ('var/lib/fusionbox/cf-guard.' + 'a' * 32 + '.state.original')).exists())


if __name__ == '__main__':
    names = [n for n in Notifications.__dict__ if n.startswith('test_')]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(Notifications(n) for n in names))
    raise SystemExit(not result.wasSuccessful())
