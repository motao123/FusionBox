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
        tls_port = freeport()
        while tls_port in (listen, upstream):
            tls_port = freeport()
        import subprocess
        def pem(name, hostname, days='2'):
            cert, key = base / (name + '.pem'), base / (name + '.key')
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(cert),
                            '-days', '2', '-subj', '/CN=' + hostname, '-addext', 'subjectAltName=DNS:' + hostname], check=True, capture_output=True)
            os.chmod(key, 0o600)
            if days == '-1':
                subprocess.run(['openssl', 'x509', '-in', str(cert), '-signkey', str(key), '-days', '-1', '-out', str(cert)], check=True, capture_output=True)
            return {'cert': str(cert), 'key': str(key), 'listen': tls_port, 'redirect': True}
        good = pem('valid', 'test.local')
        wrong = pem('wrong', 'wrong.local')
        expired = pem('expired', 'test.local', '-1')
        malformed = base / 'invalid.pem'
        malformed.write_text('invalid PEM fixture')
        def secure(expected=200, hostname='test.local'):
            for attempt in range(40):
                result = subprocess.run(['curl', '--silent', '--show-error', '--noproxy', '*', '--cacert', good['cert'],
                                         '--resolve', hostname + ':' + str(tls_port) + ':127.0.0.1',
                                         '--max-time', '3', '-w', '\\n%{http_code}', 'https://' + hostname + ':' + str(tls_port) + '/'], capture_output=True)
                if result.returncode == 0 and result.stdout.endswith(str(expected).encode()):
                    return result.stdout
                time.sleep(.1)
            raise AssertionError('Verified TLS request failed; no insecure fallback')
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
                m.operate('domain', accepted=True, project=project, domain='test.local', listen=listen)
                before = registry.read_bytes(), d.path(record()).read_bytes()
                for bad in (wrong, expired, dict(good, key=wrong['key']), dict(good, cert=str(malformed))):
                    try:
                        m.operate('tls', accepted=True, project=project, tls=bad)
                    except ValueError:
                        pass
                    else:
                        raise AssertionError('Invalid TLS material accepted')
                    assert before == (registry.read_bytes(), d.path(record()).read_bytes())
                m.operate('tls', accepted=True, project=project, tls=good)
                assert b'Welcome to nginx' in secure()
                for attempt in range(40):
                    redirect = subprocess.run(['curl', '-sS', '--noproxy', '*', '-D', '-', '-o', '/dev/null', '-H', 'Host: test.local',
                                               'http://127.0.0.1:' + str(listen)], capture_output=True, check=True).stdout
                    if b'308' in redirect and ('https://test.local:' + str(tls_port)).encode() in redirect:
                        break
                    time.sleep(.1)
                else:
                    raise AssertionError('HTTP redirect did not activate after bounded reload wait')
                wrong_host = subprocess.run(['curl', '-sS', '--noproxy', '*', '--cacert', good['cert'], '--resolve',
                                             'wrong.local:' + str(tls_port) + ':127.0.0.1', 'https://wrong.local:' + str(tls_port)], capture_output=True)
                assert wrong_host.returncode == 60
                before = registry.read_bytes(), d.path(record()).read_bytes()
                calls.clear()
                with patch.object(d, 'nginx', side_effect=failed_reload):
                    try:
                        m.operate('tls', accepted=True, project=project, tls=None)
                    except RuntimeError as error:
                        assert 'previous configuration restored' in str(error)
                    else:
                        raise AssertionError('TLS reload failure expected')
                assert before == (registry.read_bytes(), d.path(record()).read_bytes())
                assert b'Welcome to nginx' in secure()
                m.operate('tls', accepted=True, project=project, tls=dict(good, redirect=False))
                assert b'Welcome to nginx' in request('test.local')
                assert b'Welcome to nginx' in secure()
                m.operate('tls', accepted=True, project=project, tls=good)
                m.operate('status', project=project)
                m.operate('update', accepted=True, project=project)
                assert record()['market']['domain']['tls'] == good
                m.operate('uninstall', accepted=True, project=project)
                request('test.local', 503)
                secure(503)
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
                assert b'Welcome to nginx' in secure()
                assert record()['market']['domain']['enabled']
                m.operate('tls', accepted=True, project=project, tls=None)
                assert b'Welcome to nginx' in request('test.local')
                assert Path(good['cert']).exists() and Path(good['key']).exists()
                m.operate('domain', accepted=True, project=project)
                assert 'domain' not in record()['market']
                assert not d.path(record()).exists()
                print('REAL DOMAIN/TLS: 24 checks passed; HTTP routing/rollback, verified self-signed TLS, redirect, SAN/expiry/key rejection, lifecycle persistence and disable')
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
