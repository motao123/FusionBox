"""Explicit isolated ntfy API, offline SQLite backup/restore and retained-data fixture."""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
import urllib.request
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_apps as m


def run():
    if sys.argv[1:] != ['--run']:
        raise SystemExit('Explicit --run required')
    project = 'fb-ntfy-fixture-' + str(os.getpid())
    checks = []
    def check(value, name):
        assert value, name
        checks.append(name)
    with tempfile.TemporaryDirectory(prefix='fb-ntfy-fixture-') as directory:
        m.cb.BASE = Path(directory) / 'registry'
        registry = m.cb.BASE / (project + '.json')
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        def record(): return m.load(registry, project)
        def operation(action, **kwargs):
            m.operate(action, app='ntfy', project=project, accepted=True, **kwargs)
        def request(path, body=None):
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(urllib.request.Request('http://127.0.0.1:%s%s' % (port, path), data=body), timeout=5) as response:
                return response.read()
        def messages():
            return [json.loads(line)['message'] for line in request('/fixture/json?poll=1&since=all').splitlines() if line]
        def wait():
            for _ in range(45):
                if m.health(record()) == 'healthy': return
                time.sleep(1)
            raise AssertionError('API did not recover')
        try:
            operation('install', port=port)
            check(json.loads(request('/v1/health'))['healthy'] is True, 'actual health JSON')
            container = m.resources(record())[0]
            check(container['Config']['User'] == '65534:65534', 'non-root runtime')
            check(not container['HostConfig']['Privileged'], 'not privileged')
            check(container['HostConfig']['Memory'] == 128 * 1024 * 1024, 'bounded memory')
            check(all(x['Type'] == 'volume' for x in container['Mounts']), 'no docker socket/bind')
            request('/fixture', b'FusionBox persisted notification')
            check('FusionBox persisted notification' in messages(), 'publish/poll real content')
            backup = Path(directory) / 'backup.tar.gz'
            real_package = m.cb.package
            def offline_package(*args):
                check(not m.cb.js('inspect', container['Id'])[0]['State']['Running'], 'SQLite writer stopped during snapshot')
                return real_package(*args)
            with patch.object(m.cb, 'package', side_effect=offline_package):
                m.cb.operate(project, 'backup', backup, True)
            wait()
            request('/fixture', b'after snapshot')
            check('after snapshot' in messages(), 'post-backup mutation')
            m.cb.operate(project, 'restore', backup, True)
            wait()
            check('after snapshot' not in messages() and 'FusionBox persisted notification' in messages(), 'offline SQLite restore')
            before = registry.read_bytes(), Path(record()['compose']).read_bytes()
            with patch.object(m, 'pull', return_value='sha256:' + 'f' * 64):
                try: operation('update')
                except ValueError as error: check('upgrade refused' in str(error), 'migration upgrade refused')
                else: raise AssertionError('upgrade accepted')
            check(before == (registry.read_bytes(), Path(record()['compose']).read_bytes()), 'refused upgrade preserves metadata')
            operation('update')
            operation('uninstall')
            check(not m.resources(record()), 'uninstall removes container only')
            operation('reinstall', reuse=True)
            check('FusionBox persisted notification' in messages(), 'same pinned image reinstall persistence')
            identity = m.resources(record())[0]['Id']
            m.cb.docker('restart', identity); wait()
            check('FusionBox persisted notification' in messages(), 'restart persistence')
            operation('uninstall')
            real_up = m.up
            def fail_health(rec):
                real_up(rec)
                raise RuntimeError('fixture post-start health failure')
            with patch.object(m, 'up', side_effect=fail_health):
                try: operation('reinstall', reuse=True)
                except RuntimeError as error: check('newly created containers removed' in str(error), 'failed reinstall cleanup')
                else: raise AssertionError('failure not propagated')
            check(not m.resources(record()), 'failed reinstall container absent')
            operation('reinstall', reuse=True)
            check('FusionBox persisted notification' in messages(), 'retry retains data without image migration')
            print('REAL NTFY: %s checks passed' % len(checks))
        finally:
            if registry.exists():
                r = record()
                for c in m.resources(r):
                    m.cb.docker('stop', c['Id']); m.cb.docker('rm', c['Id'])
                if project + '_data' in m.cb.docker('volume', 'ls', '-q').decode().split():
                    m.cb.docker('volume', 'rm', project + '_data')
            assert not m.cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip()
            assert project + '_data' not in m.cb.docker('volume', 'ls', '-q').decode().split()
            assert not m.cb.docker('network', 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project).strip()
            print('CLEANUP: ntfy fixture containers/volume/network absent; official image cache retained')


if __name__ == '__main__':
    run()
