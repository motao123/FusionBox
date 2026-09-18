"""Explicit opt-in real Docker fixture: python3 tests/market_docker_fixture.py --run.
Creates only a unique project, with bounded Nginx resources. No existing apps changed.
"""
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.request
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_apps as m


def run():
    if sys.argv[1:] != ['--run']:
        raise SystemExit('Explicit --run required; requires local Docker Compose and root')
    project = 'fb-market-fixture-' + str(os.getpid())
    with tempfile.TemporaryDirectory(prefix='fb-market-fixture-') as directory:
        m.cb.BASE = Path(directory) / 'registry'
        import socket
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
        registry = m.cb.BASE / (project + '.json')
        def operation(action):
            m.operate(action, port=port, accepted=True, project=project)
        def record(): return m.load(registry, project)
        def content():
            with urllib.request.urlopen('http://127.0.0.1:' + str(port), timeout=5) as response:
                return response.read()
        try:
            operation('install')
            r = record()
            assert m.health(r) == 'healthy'
            assert b'Welcome to nginx' in content()
            assert registry.stat().st_mode & 0o777 == 0o600
            data, containers, paths = m.cb.inspect(r)
            volume = next(iter(paths.values()))
            (volume / 'index.html').write_text('FusionBox managed persistent content\n')
            assert b'FusionBox managed persistent content' in content()
            m.cb.operate(project, 'backup', Path(directory) / 'backup.tar.gz', True)
            import time
            for attempt in range(30):
                if m.health(r) == 'healthy':
                    break
                time.sleep(1)
            assert m.health(r) == 'healthy'
            operation('status')
            operation('update')  # current image check
            # A tiny derived image forces real recreation without downloading another app.
            # Container commit is fixture-only; application update accepts only catalog pulls.
            identity = m.resources(r)[0]['Id']
            candidate = m.cb.docker('commit', '--change', 'LABEL io.fusionbox.fixture=update', identity).decode().strip().splitlines()[-1]
            for attempt in range(30):
                if m.health(r) == 'healthy':
                    break
                time.sleep(1)
            try:
                with patch.object(m, 'pull', return_value=candidate): operation('update')
                assert record()['market']['image'] == candidate
                assert b'FusionBox managed persistent content' in content()
                original_up = m.up
                calls = []
                def fail_after_real_up(rec):
                    original_up(rec)
                    calls.append(1)
                    if len(calls) == 1:
                        raise RuntimeError('injected failed post-deployment health')
                # Switch back to original, then fail health: rollback must restore candidate.
                with patch.object(m, 'pull', return_value=r['market']['image']), patch.object(m, 'up', side_effect=fail_after_real_up):
                    try: operation('update')
                    except RuntimeError as error: assert 'previous image restored' in str(error)
                    else: raise AssertionError('expected failed update')
                assert record()['market']['image'] == candidate
                assert m.health(record()) == 'healthy'
                assert b'FusionBox managed persistent content' in content()
                operation('uninstall')
                assert not m.resources(record())
                assert (volume / 'index.html').read_text() == 'FusionBox managed persistent content\n'
                assert registry.exists() and Path(r['compose']).exists()
                operation('status')
                # Preferred port occupied: bounded selection must choose the next free slot.
                with socket.socket() as occupied:
                    occupied.bind(('127.0.0.1', 0)); occupied.listen()
                    preferred = occupied.getsockname()[1]
                    m.operate('reinstall', port=preferred, accepted=True, project=project, automatic=True, reuse=True)
                    assert preferred < record()['market']['port'] < preferred + 20
                port = record()['market']['port']
                assert b'FusionBox managed persistent content' in content()
                operation('uninstall')
                before = registry.read_bytes(), Path(r['compose']).read_bytes()
                real_select = m.select_port
                with socket.socket() as unused:
                    unused.bind(('127.0.0.1', 0)); race_port = unused.getsockname()[1]
                with socket.socket() as racer:
                    def race(preferred, automatic, **options):
                        chosen = real_select(preferred, automatic, **options)
                        racer.bind(('127.0.0.1', chosen)); racer.listen()
                        return chosen
                    with patch.object(m, 'select_port', side_effect=race):
                        try:
                            m.operate('reinstall', port=race_port, accepted=True, project=project, reuse=True)
                        except RuntimeError as error:
                            assert 'original registry/config/data retained' in str(error)
                        else:
                            raise AssertionError('expected actual Docker bind collision')
                assert before == (registry.read_bytes(), Path(r['compose']).read_bytes())
                assert not m.resources(record())
                assert (volume / 'index.html').read_text() == 'FusionBox managed persistent content\n'
                m.operate('reinstall', accepted=True, project=project, reuse=True, automatic=True)
                port = record()['market']['port']
                assert b'FusionBox managed persistent content' in content()
                operation('uninstall')
                print('REAL MARKET: 20 assertions passed; retained-data reinstall, occupied-port fallback, real bind race cleanup and retry')
            finally:
                # Only fixture-owned image created above; remove after fixture containers.
                for c in m.resources(record()):
                    m.cb.docker('stop', c['Id']); m.cb.docker('rm', c['Id'])
                m.cb.docker('image', 'rm', candidate)
        finally:
            if registry.exists():
                r = record()
                for c in m.resources(r):
                    m.cb.docker('stop', c['Id']); m.cb.docker('rm', c['Id'])
                volume_name = project + '_data'
                if volume_name in m.cb.docker('volume', 'ls', '-q').decode().split():
                    m.cb.docker('volume', 'rm', volume_name)
            assert not m.cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip()
            assert project + '_data' not in m.cb.docker('volume', 'ls', '-q').decode().split()
            assert not m.cb.docker('network', 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project).strip()
            print('CLEANUP: market fixture containers/volume/network absent; fixture image removed')


if __name__ == '__main__':
    run()
