"""OpenSSH production switch/rollback transaction tests (transaction only).

The candidate *pipeline* (signed fetch, GPG verification, build, isolated login) is
proven against the real signed release by tests/acceptance/openssh_switch.sh on a
real host. Here the candidate artifacts are fixtures so the transaction itself —
gates, atomic replace, probe polling, rollback, refusal paths — can be exercised in
CI without Docker, a compiler, or root.
"""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import openssh_candidate as candidate  # noqa: E402

FAKE_SSHD = """#!/bin/sh
case "$1" in
  -T) printf 'port %s\\npasswordauthentication no\\nkbdinteractiveauthentication no\\n' "$(sed -n 's/^Port //p' "$3")" ;;
  -t) exit 0 ;;
  -V) echo "OpenSSH_9.9p1, fixture" ;;
  *) exit 0 ;;
esac
"""


class BannerServer:
    """Minimal TCP listener that emits an SSH identification string."""

    def __init__(self, version):
        self.version = version
        self.socket = socket.socket()
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(('127.0.0.1', 0))
        self.socket.listen(8)
        self.port = self.socket.getsockname()[1]
        self.stop = False
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while not self.stop:
            try:
                connection, _ = self.socket.accept()
            except OSError:
                return
            with connection:
                try:
                    connection.sendall(('SSH-2.0-%s\r\n' % self.version).encode())
                except OSError:
                    pass

    def close(self):
        self.stop = True
        try:
            self.socket.close()
        except OSError:
            pass


def write_script(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)
    return path


@unittest.skipIf(os.name == 'nt', 'POSIX transaction semantics')
class SwitchTransaction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name) / 'state'
        self.state.mkdir()
        (self.state / '.owner').write_text(candidate.OWNER_MARKER + '\n')
        self.prefix = self.state / 'prefix/sbin'
        # The candidate must differ from the running binary, otherwise the replace is
        # a no-op and hash-based assertions cannot tell whether a switch happened.
        self.candidate = write_script(self.prefix / 'sshd', FAKE_SSHD + '# candidate build\n')
        (self.state / 'verification.json').write_text(json.dumps({
            'owner': candidate.OWNER_MARKER, 'version': candidate.OPENSSH_VERSION,
            'tarball': candidate.TARBALL_NAME, 'sha256': candidate.TARBALL_SHA256,
            'release_key_fingerprint': candidate.RELEASE_KEY_FINGERPRINT,
            'source_url': candidate.SOURCE_URL, 'verified': True}) + '\n')
        self.server = BannerServer('9.9p1-production')
        self.addCleanup(self.server.close)
        self.production = write_script(Path(self.tmp.name) / 'prod/sshd', FAKE_SSHD)
        self.config = Path(self.tmp.name) / 'prod/sshd_config'
        self.config.write_text('Port %d\n' % self.server.port)
        self.args = _args(self.state, self.production, self.config)
        patch.object(candidate, 'SWITCH_PROBE_TIMEOUT', 1).start()
        # The detached watchdog is spawned by _switch; tests must not leave stray
        # processes behind, so the spawn is stubbed and the watchdog is called directly.
        dummy = Mock(pid=1)
        patch.object(candidate, '_spawn_watchdog', return_value=dummy).start()
        self.addCleanup(patch.stopall)

    def test_gates_require_a_proven_candidate(self):
        (self.state / 'verification.json').unlink()
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, self.args)
        (self.state / 'verification.json').write_text(json.dumps({
            'owner': candidate.OWNER_MARKER, 'version': candidate.OPENSSH_VERSION,
            'sha256': candidate.TARBALL_SHA256, 'verified': True}) + '\n')
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, self.args)  # no isolated-login record yet
        (self.state / 'test.json').write_text(json.dumps({
            'owner': candidate.OWNER_MARKER, 'version': candidate.OPENSSH_VERSION,
            'independent_login': True, 'config_valid': True, 'effective_config_valid': True}) + '\n')
        gate = candidate._switch_gates(self.state, self.args)
        self.assertEqual(gate['port'], self.server.port)
        self.assertIn('9.9p1-production', gate['banner'])

    def test_test_record_without_login_is_rejected(self):
        (self.state / 'test.json').write_text(json.dumps({
            'owner': candidate.OWNER_MARKER, 'version': candidate.OPENSSH_VERSION,
            'independent_login': False, 'config_valid': True, 'effective_config_valid': True}) + '\n')
        with self.assertRaises(candidate.CandidateError):
            candidate._load_test_record(self.state)

    def test_symlinked_production_path_is_refused(self):
        link = Path(self.tmp.name) / 'prod/link'
        link.symlink_to(self.production)
        args = _args(self.state, link, self.config)
        _prepare(self.state)
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, args)

    def test_dead_production_listener_is_refused(self):
        # Use a port nothing is listening on, obtained without relying on close()
        # semantics of a threaded listener (that was itself a source of flakiness).
        probe = socket.socket()
        probe.bind(('127.0.0.1', 0))
        dead = probe.getsockname()[1]
        probe.close()
        self.config.write_text('Port %d\n' % dead)
        _prepare(self.state)
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, self.args)

    def test_dry_run_changes_nothing(self):
        _prepare(self.state)
        before = self.production.read_bytes()
        record = candidate._switch(self.state, _args(self.state, self.production, self.config, dry_run=True))
        self.assertEqual(record['status'], 'verified')
        self.assertIn('dry run', record['detail'])
        self.assertEqual(self.production.read_bytes(), before)
        self.assertFalse(candidate._switch_record_path(self.state).exists())

    def test_switch_verifies_then_rollback_restores(self):
        _prepare(self.state)
        original = self.production.read_bytes()
        record = candidate._switch(self.state, self.args)
        self.assertEqual(record['status'], 'verified')
        self.assertNotEqual(self.production.read_bytes(), original)
        self.assertEqual(record['after_sha256'], candidate._hash(self.production))
        saved = candidate._load_switch_record(self.state)
        self.assertEqual(saved['status'], 'verified')
        self.assertTrue((self.state / saved['backup']).is_file())
        candidate._rollback(self.state, self.args)
        self.assertEqual(self.production.read_bytes(), original)
        self.assertEqual(candidate._load_switch_record(self.state)['status'], 'rolled-back')
        with self.assertRaises(candidate.CandidateError):
            candidate._rollback(self.state, self.args)  # already restored: never guess

    def test_switch_rolls_back_when_the_new_binary_never_serves(self):
        _prepare(self.state)
        original = self.production.read_bytes()
        # Production answers the pre-flight gate, but nothing answers afterwards: the
        # probe must fail and the transaction must put the previous binary back itself.
        calls = {'n': 0}

        def banner(port, timeout=2):
            calls['n'] += 1
            return 'SSH-2.0-9.9p1-production' if calls['n'] == 1 else None

        with patch.object(candidate, '_banner', side_effect=banner):
            record = candidate._switch(self.state, self.args)
        self.assertEqual(record['status'], 'rolled-back')
        self.assertEqual(self.production.read_bytes(), original)
        self.assertIn('did not answer', record['detail'])

    def test_watchdog_undoes_a_switch_that_stopped_serving(self):
        _prepare(self.state)
        original = self.production.read_bytes()
        record = candidate._switch(self.state, self.args)
        self.assertEqual(record['status'], 'verified')
        record['status'] = 'verifying'
        candidate._save_switch_record(self.state, record)
        with patch.object(candidate, '_banner', return_value=None):
            self.assertEqual(candidate._watchdog(self.state, candidate._settings(self.args), 1), 1)
        self.assertEqual(self.production.read_bytes(), original)
        self.assertEqual(candidate._load_switch_record(self.state)['status'], 'auto-rolled-back')

    def test_probe_polls_through_the_reload_window(self):
        """A single immediate probe raced the re-exec and caused a false rollback."""
        calls = {'n': 0}

        def flaky(port, timeout=2):
            calls['n'] += 1
            return None if calls['n'] < 3 else 'SSH-2.0-OpenSSH_test'

        with patch.object(candidate, '_banner', side_effect=flaky):
            banner = candidate._wait_for_banner(1234, timeout=5, interval=0.01)
        self.assertEqual(banner, 'SSH-2.0-OpenSSH_test')
        self.assertEqual(calls['n'], 3)

    def test_missing_verification_record_is_refused(self):
        _prepare(self.state)
        (self.state / 'verification.json').unlink()
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, self.args)

    def test_rollback_without_a_switch_is_refused(self):
        with self.assertRaises(candidate.CandidateError):
            candidate._rollback(self.state, self.args)

    def test_watchdog_keeps_a_healthy_switch(self):
        _prepare(self.state)
        record = candidate._switch(self.state, self.args)
        record['status'] = 'verifying'
        candidate._save_switch_record(self.state, record)
        self.assertEqual(candidate._watchdog(self.state, candidate._settings(self.args), 1), 0)
        self.assertEqual(candidate._load_switch_record(self.state)['status'], 'verified')

    def test_config_drift_requires_explicit_acceptance(self):
        _prepare(self.state)
        drifted = FAKE_SSHD + '# candidate build\n'
        drifted = drifted.replace('passwordauthentication no', 'passwordauthentication yes')
        self.candidate.write_text(drifted)
        self.candidate.chmod(0o755)
        with self.assertRaises(candidate.CandidateError):
            candidate._switch_gates(self.state, _args(self.state, self.production, self.config,
                                                      accept_drift=False))
        gate = candidate._switch_gates(self.state, _args(self.state, self.production, self.config,
                                                        accept_drift=True))
        self.assertIn('passwordauthentication', gate['drift'])


def _args(state, binary, config, dry_run=False, accept_drift=True):
    class Args:
        pass

    args = Args()
    args.state_dir = str(state)
    args.sshd_path = str(binary)
    args.config = str(config)
    args.pid_file = str(Path(config).parent / 'sshd.pid')
    args.reload_command = 'true'
    args.restart_command = 'true'
    args.accept_config_drift = accept_drift
    args.dry_run = dry_run
    args.grace = 1
    return args


def _prepare(state):
    (state / 'test.json').write_text(json.dumps({
        'owner': candidate.OWNER_MARKER, 'version': candidate.OPENSSH_VERSION,
        'independent_login': True, 'config_valid': True, 'effective_config_valid': True}) + '\n')


if __name__ == '__main__':
    unittest.main()
