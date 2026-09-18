"""Opt-in isolated host-network Nginx fixture; only ephemeral high ports are used."""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
import urllib.request
import urllib.error
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import market_apps as m
import market_domain as d


def freeport():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def run():
    if sys.argv[1:] != ['--run']:
        raise SystemExit('Explicit --run required')
    project = 'fb-domain-fixture-' + str(os.getpid())
    proxy = project + '-proxy'
    with tempfile.TemporaryDirectory(prefix='fb-domain-') as folder:
        base = Path(folder)
        m.cb.BASE = base / 'registry'
        d.CONF = base / 'conf.d'
        d.CONF.mkdir()
        listen = freeport()
        upstream = freeport()
        while upstream == listen:
            upstream = freeport()
        main = base / 'nginx.conf'
        main.write_text('pid /tmp/fixture-nginx.pid;\nevents {}\nhttp { access_log off; include ' + str(d.CONF) + '/*.conf; }\n')
        registry = m.cb.BASE / (project + '.json')
        def record(): return m.load(registry, project)
        def nginx(*args):
            if '-c' not in args:
                args = (*args, '-c', str(main))
            import subprocess
            result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', 'exec', proxy, 'nginx', *args], capture_output=True, text=True)
            if result.returncode:
                print('Fixture Nginx diagnostics:', result.stderr, flush=True)
                raise RuntimeError('Fixture Nginx: ' + result.stderr)
            return result.stdout + result.stderr
        def request(host, expected=200):
            for attempt in range(40):
                try:
                    req = urllib.request.Request('http://127.0.0.1:' + str(listen), headers={'Host': host})
                    with urllib.request.urlopen(req, timeout=2) as res:
                        if res.status == expected:
                            return res.read()
                except urllib.error.HTTPError as error:
                    if error.code == expected:
                        return b''
                except OSError:
                    pass
                time.sleep(.1)
            raise AssertionError('HTTP route did not reach expected status ' + str(expected))
        proxy_started = False
        try:
            m.operate('install', port=upstream, accepted=True, project=project)
            m.cb.docker('run', '-d', '--name', proxy, '--entrypoint', 'nginx', '--network', 'host', '--memory', '64m', '--cpus', '0.5', '--pids-limit', '64',
                        '--mount', 'type=bind,src=' + folder + ',dst=' + folder,
                        record()['market']['image'], '-c', str(main), '-g', 'daemon off;')
            proxy_started = True
            with patch.object(d, 'nginx', side_effect=nginx):
                m.operate('domain', accepted=True, project=project, domain='app.example.test', listen=listen)
                assert b'Welcome to nginx' in request('app.example.test')
                request('wrong.example.test', 404)
                before = registry.read_bytes(), d.path(record()).read_bytes()
                calls = []
                def failed_reload(*args):
                    if args[:2] == ('-s', 'reload'):
                        calls.append(1)
                        if len(calls) == 1:
                            raise RuntimeError('injected reload failure')
                    return nginx(*args)
                with patch.object(d, 'nginx', side_effect=failed_reload):
                    try:
                        m.operate('domain', accepted=True, project=project, domain='new.example.test', listen=listen)
                    except RuntimeError as error:
                        assert 'previous configuration restored' in str(error)
                    else:
                        raise AssertionError('reload failure expected')
                assert before == (registry.read_bytes(), d.path(record()).read_bytes())
                assert b'Welcome to nginx' in request('app.example.test')
                other = d.CONF / 'other.conf'
                other.write_text('server { listen ' + str(listen) + '; server_name collision.example.test; return 204; }\n')
                try:
                    m.operate('domain', accepted=True, project=project, domain='collision.example.test', listen=listen)
                except ValueError as error:
                    assert 'collides' in str(error)
                else:
                    raise AssertionError('collision expected')
                other.unlink()
                assert before == (registry.read_bytes(), d.path(record()).read_bytes())
                m.operate('update', accepted=True, project=project)
                assert record()['market']['domain']['name'] == 'app.example.test'
                m.operate('uninstall', accepted=True, project=project)
                request('app.example.test', 503)
                assert not record()['market']['domain']['enabled']
                # HTTP clients can leave TIME_WAIT on the upstream; use the normal
                # conservative preflight and retry only EADDRINUSE, bounded.
                import errno
                for attempt in range(75):
                    try:
                        m.operate('reinstall', accepted=True, reuse=True, project=project)
                        break
                    except OSError as error:
                        if error.errno != errno.EADDRINUSE or attempt == 74:
                            raise
                        time.sleep(1)
                assert b'Welcome to nginx' in request('app.example.test')
                assert record()['market']['domain']['enabled']
                m.operate('domain', accepted=True, project=project)
                assert 'domain' not in record()['market']
                assert not d.path(record()).exists()
                print('REAL DOMAIN: 12 checks passed; Host routing/rejection, reload rollback, collision, update/uninstall/reinstall persistence, removal')
        finally:
            if proxy_started:
                m.cb.docker('rm', '-f', proxy)
            if registry.exists():
                for container in m.resources(record()):
                    m.cb.docker('stop', container['Id'])
                    m.cb.docker('rm', container['Id'])
                if project + '_data' in m.cb.docker('volume', 'ls', '-q').decode().split():
                    m.cb.docker('volume', 'rm', project + '_data')
            print('CLEANUP: isolated domain proxy/app/volume removed; host Nginx untouched')


if __name__ == '__main__':
    run()
