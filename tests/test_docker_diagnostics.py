"""Read-only Docker diagnostics contract and failure regressions (no engine needed)."""
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / 'src/modules/panels.sh').as_posix()
MOCK = r'''
docker() {
  case "$*" in
    'info '*) printf 'Engine=27 Images=4\n' ;;
    'container ls '*) printf 'running\npaused\nexited\ncreated\ndead\nrestarting\nremoving\n' ;;
    'network ls '*) printf 'id1 bridge bridge local\nid2 fixture bridge local\n' ;;
    'volume ls '*) printf 'data local\n' ;;
    'system df') printf 'TYPE TOTAL SIZE RECLAIMABLE\nImages 4 10MB 0B\n' ;;
    *) return 91 ;;
  esac
}
'''

class Diagnostics(unittest.TestCase):
    def run_shell(self, body, mock=MOCK):
        return subprocess.run(['bash', '-c', 'source "$1"\n' + mock + '\n' + body, 'test', MODULE],
                              text=True, capture_output=True, env={**os.environ, 'MSYS_NO_PATHCONV': '1'})

    def test_state_counts(self):
        p = self.run_shell('panels_docker summary')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('Containers=7 Running=1 Paused=1 Stopped=3 Exited=1', p.stdout)
        self.assertIn('Networks=2 Volumes=1', p.stdout)
        self.assertIn('Images=4', p.stdout)

    def test_empty_engine(self):
        p = self.run_shell('panels_docker_summary', 'docker() { [[ "$1" != info ]] || printf "Engine=27 Images=0\\n"; return 0; }')
        self.assertEqual(p.returncode, 0)
        self.assertIn('Containers=0', p.stdout)

    def test_daemon_and_permission_failures(self):
        for message in ('Cannot connect to daemon', 'permission denied SECRET'):
            p = self.run_shell('panels_docker summary', 'docker() { printf "%s\\n" "' + message + '" >&2; return 1; }')
            self.assertNotEqual(p.returncode, 0)
            self.assertEqual(p.stdout, '')
            self.assertIn('permissions', p.stderr)
            self.assertNotIn('SECRET', p.stderr)

    def test_absent_cli(self):
        p = self.run_shell('PATH=/nonexistent; panels_docker_summary', '')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('not installed', p.stderr)

    def test_each_summary_query_failure(self):
        for command in ('container', 'network', 'volume', 'system'):
            mock = MOCK.replace('case "$*" in', '[[ "$1" != ' + command + ' ]] || return 1\n  case "$*" in')
            p = self.run_shell('panels_docker_summary', mock)
            self.assertNotEqual(p.returncode, 0)
            self.assertEqual(p.stdout, '')

    def test_unknown_state(self):
        p = self.run_shell('panels_docker_summary', MOCK.replace('running\\npaused', 'unknown\\npaused'))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(p.stdout, '')

    def test_reject_invalid_targets_before_docker(self):
        for target in ('', '--help', '../x', 'x y', 'x;id', 'x\nsecret', 'a' * 256):
            p = self.run_shell('panels_docker_detail ' + "'" + target + "'", 'docker() { printf CALLED; return 0; }')
            self.assertEqual(p.returncode, 2)
            self.assertNotIn('CALLED', p.stdout)

    def test_bad_arity(self):
        for args in ('summary --invalid', 'summary --all extra', 'detail a b'):
            self.assertEqual(self.run_shell('panels_docker ' + args).returncode, 2)

    def test_missing_container(self):
        p = self.run_shell('panels_docker detail missing', 'docker() { return 1; }')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(p.stdout, '')

    def test_stopped_skips_stats_and_allowlist(self):
        mock = r'''
docker() {
  [[ "$1 $2" == 'container inspect' ]] || return 99
  [[ "$4" != *'.Config.Env'* && "$4" != *'.Config.Cmd'* && "$4" != *'.State.Health.Log'* ]] || return 98
  printf 'ID=abc\nState=exited\nEnvironment=[redacted: all values omitted]\n'
}
'''
        p = self.run_shell('panels_docker detail fixture', mock)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('RuntimeUsage=not sampled', p.stdout)
        self.assertIn('NanoCPUs=0', p.stdout)

    def test_runtime_failure_propagates(self):
        mock = r'''docker() { if [[ "$2" == inspect ]]; then printf 'ID=abc\nState=running\n'; else return 1; fi; }'''
        p = self.run_shell('panels_docker detail fixture', mock)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('RuntimeUsage=unavailable', p.stderr)

    def test_stats_uses_inspected_id(self):
        mock = r'''docker() { if [[ "$2" == inspect ]]; then printf 'ID=abc123\nState=running\n'; else [[ "${@: -1}" == abc123 ]] || return 1; printf 'RuntimeUsage: CPU=0.00%%\n'; fi; }'''
        p = self.run_shell('panels_docker detail fixture', mock)
        self.assertEqual(p.returncode, 0)
        self.assertIn('RuntimeUsage: CPU=0.00%', p.stdout)

if __name__ == '__main__':
    unittest.main()
