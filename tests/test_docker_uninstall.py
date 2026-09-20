"""Docker port-block and uninstall flow tests; docker/iptables/package commands are mocked."""
from test_safety import Safety


IPT_SAVE = (
    '-A DOCKER-USER -p tcp -d 172.18.0.2 --dport 80 -m comment --comment "fb-port-block:web:tcp:80" -j DROP\n'
    '-A DOCKER-USER -p udp -d 172.18.0.3 --dport 53 -m comment --comment "fb-port-block:dns:udp:53" -j DROP\n'
    '-A DOCKER-USER -j RETURN\n'
)


class PortBlock(Safety):
    def mocks(self, ips='172.18.0.2', save=IPT_SAVE, chain_ok=0):
        return (
            'iptables() { case "$*" in *"-nL DOCKER-USER"*) return %(chain)d;; *) printf "%%s\\n" "$*" >> "$T/ipt";; esac; }\n'
            'iptables-save() { printf \'%%b\' \'%(save)s\'; }\n'
            'docker() { case "$1" in inspect) printf "%(ips)s ";; *) printf "docker %%s\\n" "$*" >> "$T/ipt";; esac; }\n'
        ) % {'chain': chain_ok, 'save': save.replace('\n', '\\n'), 'ips': ips}

    def test_add_inserts_marked_rule(self):
        body = self.mocks() + 'confirm() { return 0; }\n' \
            'panels_docker_port_block add web tcp 80 || exit 9'
        self.run_shell('panels', body)
        ipt = (self.root / 'ipt').read_text()
        self.assertIn('-I DOCKER-USER 1 -p tcp -d 172.18.0.2 --dport 80', ipt)
        self.assertIn('fb-port-block:web:tcp:80', ipt)
        self.assertIn('-j DROP', ipt)

    def test_add_refuses_bad_input_before_iptables(self):
        body = self.mocks() + 'panels_docker_port_block add "bad name" tcp 80 || exit 9'
        self.run_shell('panels', body, 9)
        body = self.mocks() + 'panels_docker_port_block add web sctp 80 || exit 9'
        self.run_shell('panels', body, 9)
        body = self.mocks() + 'panels_docker_port_block add web tcp 70000 || exit 9'
        self.run_shell('panels', body, 9)
        self.assertFalse((self.root / 'ipt').exists())

    def test_add_missing_container_refused(self):
        body = self.mocks(ips='') + 'confirm() { return 0; }\n' \
            'panels_docker_port_block add ghost tcp 80 || exit 9'
        self.run_shell('panels', body, 9)
        if (self.root / 'ipt').exists():
            self.assertNotIn('-I DOCKER-USER 1', (self.root / 'ipt').read_text())

    def test_add_chain_missing_refused(self):
        body = self.mocks(chain_ok=1) + 'panels_docker_port_block add web tcp 80 || exit 9'
        self.run_shell('panels', body, 9)
        self.assertFalse((self.root / 'ipt').exists())

    def test_add_failed_insert_rolls_back(self):
        mocks = self.mocks(ips='172.18.0.2 172.18.0.3', save='')
        mocks += ('iptables() { case "$*" in *"-nL DOCKER-USER"*) return 0;; *172.18.0.2*) '
                  'printf "%s\\n" "$*" >> "$T/ipt"; return 0;; *) return 1;; esac; }\n')
        body = mocks + 'confirm() { return 0; }\n' \
            'panels_docker_port_block add web tcp 80 || exit 9'
        self.run_shell('panels', body, 9)
        ipt = (self.root / 'ipt').read_text()
        self.assertIn('-I DOCKER-USER 1 -p tcp -d 172.18.0.2 --dport 80', ipt)
        self.assertIn('-D DOCKER-USER -p tcp -d 172.18.0.2 --dport 80', ipt)
        self.assertNotIn('-D DOCKER-USER -p tcp -d 172.18.0.3', ipt)

    def test_del_removes_by_comment_match(self):
        body = self.mocks() + 'panels_docker_port_block del web tcp 80 || exit 9'
        self.run_shell('panels', body)
        ipt = (self.root / 'ipt').read_text()
        self.assertIn('-D DOCKER-USER -p tcp -d 172.18.0.2 --dport 80', ipt)
        self.assertNotIn('172.18.0.3', ipt)

    def test_del_no_matching_rule_fails(self):
        body = self.mocks() + 'panels_docker_port_block del other tcp 22 || exit 9'
        self.run_shell('panels', body, 9)
        self.assertFalse((self.root / 'ipt').exists())

    def test_list_shows_managed_rules_only(self):
        body = self.mocks() + 'panels_docker_port_block list || exit 9'
        out = self.run_shell('panels', body)
        self.assertIn('fb-port-block:web:tcp:80', out)
        self.assertIn('fb-port-block:dns:udp:53', out)
        self.assertNotIn('RETURN', out)


class Uninstall(Safety):
    def mocks(self):
        return (
            'command() { if [[ "$1" == "-v" && "$2" == docker && -n "${PURGED:-}" ]]; then return 1; fi; builtin command "$@"; }\n'
            'rm() { printf "rm %s\\n" "$*" >> "$T/rm"; }\n'
            'docker() { case "$1 $2" in\n'
            '  "ps -aq") printf "c1\\nc2\\n";;\n'
            '  "images -aq") printf "i1\\n";;\n'
            '  "volume ls -q") printf "v1\\n";;\n'
            '  "network ls -q") printf "n1\\n";;\n'
            '  *) :;; esac; return 0; }\n'
            'systemctl() { :; }\n'
            'apt-get() { printf "apt-get %s\\n" "$*" >> "$T/apt"; PURGED=1; }\n'
            'dpkg() { [[ "$1 $2" == "-s docker-ce" || "$1 $2" == "-s containerd.io" ]]; }\n'
            'du() { :; }\n'
            'confirm() { return 0; }\n'
            'F_PKG_MGR=apt\n'
        )

    def test_no_gate_input_cancels_everything(self):
        body = self.mocks() + 'printf "no\\n" | panels_docker_uninstall' + '\n'
        self.run_shell('panels', body, 1)
        self.assertFalse((self.root / 'apt').exists())
        self.assertFalse((self.root / 'rm').exists())

    def test_wrong_confirmation_cancels(self):
        body = self.mocks() + 'printf "NOT-YES\\n" | panels_docker_uninstall' + '\n'
        self.run_shell('panels', body, 1)
        self.assertFalse((self.root / 'apt').exists())

    def test_uninstall_purges_and_wipes(self):
        body = self.mocks() + 'printf "YES\\nyes\\n" | panels_docker_uninstall || exit 9' + '\n'
        self.run_shell('panels', body)
        apt = (self.root / 'apt').read_text()
        self.assertIn('apt-get purge -y docker-ce containerd.io', apt)
        rm = (self.root / 'rm').read_text()
        self.assertIn('/var/lib/docker', rm)
        self.assertIn('/etc/docker', rm)

    def test_uninstall_keep_preserves_data_dirs(self):
        body = self.mocks() + 'printf "YES\\nkeep\\n" | panels_docker_uninstall || exit 9' + '\n'
        self.run_shell('panels', body)
        apt = (self.root / 'apt').read_text()
        self.assertIn('purge', apt)
        self.assertFalse((self.root / 'rm').exists())


if __name__ == '__main__':
    import unittest
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PortBlock)
    suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(Uninstall))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
