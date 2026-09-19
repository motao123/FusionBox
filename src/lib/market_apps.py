"""Small opt-in managed catalog. Never imports or executes legacy installer metadata."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sys
import uuid
import urllib.request


import compose_backup as cb
from backup_jobs import atomic
import market_domain

OWNER = 'fusionbox-market-v1'
CATALOG = {
    'nginx': {'image': 'nginx:stable-alpine', 'port': 8080, 'bytes': 256 * 1024 * 1024,
              'target': 80, 'mount': '/usr/share/nginx/html', 'readonly': True,
              'memory': '64m', 'health': ['CMD', 'wget', '-q', '-O', '/dev/null', 'http://127.0.0.1/'],
              'domain': True, 'description': 'static web server; read-only persistent content'},
    'ntfy': {'image': 'binwiederhier/ntfy:v2.28.0@sha256:6ef4b819f722fccdc036af611c4774cfdc2de821ab74fdd48bbf4c9d6f8973da',
             'port': 8081, 'bytes': 512 * 1024 * 1024, 'target': 8080,
             'mount': '/tmp', 'readonly': False, 'memory': '128m', 'user': '65534:65534',
             'command': ['serve', '--listen-http', ':8080', '--cache-file', '/tmp/ntfy-cache.db', '--cache-duration', '24h'],
             'health': ['CMD-SHELL', 'wget -q -O - http://127.0.0.1:8080/v1/health | grep -q \'"healthy":true\''],
             'health_json': '/v1/health', 'domain': False,
             'description': 'local notification server; 24h SQLite message cache; no auth; local users can publish/read; no attachments or domain/TLS; image upgrades refused'},
    'uptime-kuma': {'image': 'louislam/uptime-kuma:1@sha256:70233f4acb5163fd2a59a49909cf01e44415cecff13dba69e3a86647a2919f83',
                    'port': 8082, 'bytes': 1536 * 1024 * 1024, 'target': 3001,
                    'mount': '/app/data', 'readonly': False, 'memory': '512m',
                    'health': ['CMD', 'node', 'extra/healthcheck.js'],
                    'domain': False,
                    'description': 'uptime monitoring panel; runs as container root user (image default); localhost only; no domain/TLS mapping; image upgrades refused'},
    'ddns-go': {'image': 'jeessy/ddns-go:latest@sha256:0336e6eddcb4052e978c90f0aa530f77205b1dd08fe28057869dbc77a60c5671',
                'port': 8083, 'bytes': 512 * 1024 * 1024, 'target': 9876,
                'mount': '/root', 'readonly': False, 'memory': '64m',
                'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:9876/ || exit 1'],
                'domain': False,
                'description': 'DDNS updater with web UI; runs as container root user (image default); config in named volume; localhost only; no domain/TLS; image upgrades refused'},
    'new-api': {'image': 'calciumion/new-api:latest@sha256:0a4d62b1b2b796a43a5e0ef92d49f12e0f229ab206b8f5a3a4cd42990121bfe1',
                'port': 8084, 'bytes': 1024 * 1024 * 1024, 'target': 3000,
                'mount': '/data', 'readonly': False, 'memory': '512m',
                'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:3000/api/status || exit 1'],
                'domain': False,
                'description': 'LLM API gateway and billing panel (new-api); SQLite in named volume; runs as container root user (image default); no auth on first setup, set admin password immediately; localhost only; no domain/TLS; image upgrades refused'},
    'lobe-chat': {'image': 'lobehub/lobe-chat:latest@sha256:b2d2454525523d9f0a19c79661f83ec45f13363dbadd5c1180887e77af35d872',
                  'port': 8085, 'bytes': 1024 * 1024 * 1024, 'target': 3210,
                  'mount': '/app/data', 'readonly': False, 'memory': '1536m',
                  'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:3210/ || exit 1'],
                  'domain': False,
                  'description': 'LobeChat AI chat aggregator (ChatGPT/Claude/Gemini/Ollama keys configured in web UI); localhost only; no domain/TLS; image upgrades refused'},
    'open-webui': {'image': 'ghcr.io/open-webui/open-webui:main@sha256:1a6399d237dc392a2313e0ca826020b3fd5d22536357840eb63393d18dc8b924',
                   'port': 8086, 'bytes': 6 * 1024 * 1024 * 1024, 'target': 8080,
                   'mount': '/app/backend/data', 'readonly': False, 'memory': '1024m',
                   'health': ['CMD-SHELL', 'curl -f http://127.0.0.1:8080/health || exit 1'],
                   'health_retries': 300, 'domain': False,
                   'description': 'OpenWebUI self-hosted AI chat (Ollama/OpenAI endpoints configured in web UI); large image ~4GiB; localhost only; no domain/TLS; image upgrades refused'},
    'n8n': {'image': 'n8nio/n8n:latest@sha256:b73045abaddb40cb4024e86eea1b1f69093501a7339f685a4cd486b7743d23ae',
            'port': 8087, 'bytes': 1024 * 1024 * 1024, 'target': 5678,
            'mount': '/home/node/.n8n', 'readonly': False, 'memory': '512m',
            'environment': {'N8N_SECURE_COOKIE': 'false', 'GENERIC_TIMEZONE': 'Asia/Shanghai'},
            'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:5678/healthz || exit 1'],
            'health_retries': 30, 'domain': False,
            'description': 'n8n workflow automation; SQLite in named volume; localhost HTTP means secure cookies disabled; set owner account on first setup; no domain/TLS; image upgrades refused'},
    'openlist': {'image': 'openlistteam/openlist:latest-aria2@sha256:3d6df7eac92fd35909672fb2acab1db17e8d66bcb13abfdc12ad479de2928b41',
                 'port': 8088, 'bytes': 1024 * 1024 * 1024, 'target': 5244,
                 'mount': '/opt/openlist/data', 'readonly': False, 'memory': '256m',
                 'environment': {'PUID': '0', 'PGID': '0', 'UMASK': '022'},
                 'health_retries': 60,
                 'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:5244/ || exit 1'],
                 'domain': False,
                 'description': 'OpenList file list program with WebDAV (Alist fork); admin password via container CLI; localhost only; no domain/TLS; image upgrades refused'},
    'navidrome': {'image': 'deluan/navidrome:latest@sha256:a384948b81bd1529986c5960169e7fc4fa00f46bde6bd517971a4c36671db2af',
                  'port': 8089, 'bytes': 1024 * 1024 * 1024, 'target': 4533,
                  'mounts': [{'suffix': 'data', 'dest': '/data', 'readonly': False},
                             {'suffix': 'music', 'dest': '/music', 'readonly': True}],
                  'memory': '256m',
                  'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:4533/ || exit 1'],
                  'domain': False,
                  'description': 'Navidrome music streaming server; copy audio files into the music named volume (docker cp); localhost only; no domain/TLS; image upgrades refused'},
}


def app_mounts(spec):
    """Normalize a catalog spec into the internal mount list."""
    if 'mounts' in spec:
        mounts = spec['mounts']
    else:
        mounts = [{'suffix': 'data', 'dest': spec['mount'], 'readonly': spec['readonly']}]
    for m in mounts:
        if (not isinstance(m, dict) or not re.fullmatch(r'[a-z][a-z0-9-]{0,15}', m.get('suffix', '')) or
                not isinstance(m.get('dest'), str) or not m.get('dest', '').startswith('/') or
                not isinstance(m.get('readonly'), bool)):
            raise ValueError('Invalid catalog metadata')
    return mounts


def metadata(app):
    if app not in CATALOG:
        raise ValueError('Unsupported managed application')
    spec = CATALOG[app]
    has_mount = type(spec.get('mount')) is str and spec['mount'].startswith('/')
    if (type(spec.get('bytes')) is not int or spec['bytes'] <= 0 or
            type(spec.get('target')) is not int or not 1 <= spec['target'] <= 65535 or
            type(spec.get('port')) is not int or not 1024 <= spec['port'] <= 65535 or
            (not has_mount and 'mounts' not in spec) or
            not re.fullmatch(r'[a-z0-9./:_@-]+', spec.get('image', '')) or
            not re.fullmatch(r'[1-9][0-9]*m', spec.get('memory', '')) or
            not isinstance(spec.get('health'), list) or not spec['health']):
        raise ValueError('Invalid catalog metadata')
    if 'health_retries' in spec and (type(spec['health_retries']) is not int or
                                     not 1 <= spec['health_retries'] <= 300):
        raise ValueError('Invalid catalog metadata')
    app_mounts(spec)
    if 'environment' in spec:
        env = spec['environment']
        if (not isinstance(env, dict) or not env or
                any(not isinstance(k, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) or
                    not isinstance(v, str) for k, v in env.items())):
            raise ValueError('Invalid catalog metadata')
    return spec


def document(record, image=None):
    m = record['market']
    spec = metadata(m['app'])
    labels = {'io.fusionbox.market': m['token']}
    mounts = app_mounts(spec)
    result = {'services': {'app': {
        'image': image or m['image'], 'container_name': record['project'] + '-app',
        'network_mode': 'bridge', 'restart': 'unless-stopped',
        'ports': ['127.0.0.1:%s:%s' % (m['port'], spec['target'])],
        'volumes': [('' + suffix + ':' + mount['dest'] + (':ro' if mount['readonly'] else ''))
                    for suffix, mount in ((m['suffix'], m) for m in mounts)],
        'labels': labels,
        'mem_limit': spec['memory'], 'cpus': '0.50', 'pids_limit': 64,
        'logging': {'driver': 'json-file', 'options': {'max-size': '5m', 'max-file': '2'}},
        'healthcheck': {'test': spec['health'],
                        'interval': '2s', 'timeout': '2s',
                        'retries': spec.get('health_retries', 10)}}},
        'volumes': {m['suffix']: {'name': record['project'] + '_' + m['suffix'], 'labels': labels}
                    for m in mounts}}
    service = result['services']['app']
    if 'environment' in spec:
        service['environment'] = dict(spec['environment'])
    if 'user' in spec:
        service.update(user=spec['user'], command=spec['command'], init=True,
                       cap_drop=['ALL'], security_opt=['no-new-privileges:true'])
    return result


def save(path, record):
    atomic(path, json.dumps(record) + '\n')


def write_compose(record, image=None):
    atomic(Path(record['compose']), json.dumps(document(record, image)) + '\n')


def load(path, project):
    record = cb.load(path, project)
    m = record.get('market', {})
    if (m.get('owner') != OWNER or m.get('app') not in CATALOG or
            not re.fullmatch('[a-f0-9]{32}', m.get('token', '')) or
            not re.fullmatch('sha256:[a-f0-9]{64}', m.get('image', '')) or
            type(m.get('port')) is not int or not 1024 <= m['port'] <= 65535 or
            record['compose'] != str((cb.BASE / (project + '.compose.json')).absolute())):
        raise ValueError('Unknown managed application ownership/type')
    cb.no_links(Path(record['compose']))
    if json.loads(Path(record['compose']).read_text()) != document(record):
        raise ValueError('Managed Compose configuration changed; manual recovery required')
    return record


def resources(record):
    """Check exact resource names and labels before any stop/remove/recreate."""
    project, token = record['project'], record['market']['token']
    spec = metadata(record['market']['app'])
    ids = cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).decode().split()
    named = cb.docker('ps', '-aq', '--filter', 'name=^/' + project + '-app$').decode().split()
    if set(ids) != set(named) or len(ids) > 1:
        raise ValueError('Unknown container ownership')
    containers = cb.js('inspect', *ids) if ids else []
    for c in containers:
        labels = c['Config'].get('Labels') or {}
        if (labels.get('io.fusionbox.market') != token or
                labels.get('com.docker.compose.service') != 'app' or
                labels.get('com.docker.compose.project.config_files') != record['compose'] or
                c['HostConfig'].get('NetworkMode') != 'bridge' or
                c['HostConfig'].get('Privileged')):
            raise ValueError('Unknown container ownership/type')
        if 'user' in spec and c['Config'].get('User') != spec['user']:
            raise ValueError('Unexpected application runtime user')
        expected = {(project + '_' + m['suffix'], m['dest'], not m['readonly'])
                    for m in app_mounts(spec)}
        actual = {(mount.get('Name'), mount.get('Destination'), mount['RW'])
                  for mount in c.get('Mounts', []) if mount['Type'] == 'volume'}
        if actual != expected:
            raise ValueError('Unexpected application storage')
    volumes = cb.docker('volume', 'ls', '-q').decode().split()
    for m in app_mounts(spec):
        name = project + '_' + m['suffix']
        if name in volumes:
            v = cb.js('volume', 'inspect', name)[0]
            labels = v.get('Labels') or {}
            if (labels.get('io.fusionbox.market') != token or
                    labels.get('com.docker.compose.project') != project or
                    v['Driver'] != 'local' or v.get('Options')):
                raise ValueError('Unknown data volume ownership')
            users = cb.docker('ps', '-aq', '--filter', 'volume=' + name).decode().split()
            if set(users) - set(ids):
                raise ValueError('Data volume shared outside managed app')
        elif containers:
            raise ValueError('Managed data volume missing')
    return containers


def preflight(port, check_port=True, app='nginx'):
    if type(port) is not int or not 1024 <= port <= 65535:
        raise ValueError('Port must be 1024-65535')
    cb.docker('compose', 'version')
    root = Path(cb.js('info', '--format', '{{json .DockerRootDir}}'))
    required = metadata(app)['bytes']
    for path in (cb.BASE, root):
        if shutil.disk_usage(path).free < required:
            raise ValueError('Insufficient disk space (%s MiB required on registry and Docker storage)' % (required // 1024 // 1024))
    if check_port:
        with socket.socket() as probe:
            # Ignore closed HTTP connection TIME_WAIT, never an active listener.
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind(('127.0.0.1', port))
        # Docker may publish without a userspace listening socket.
        ids = cb.docker('ps', '-q').decode().split()
        for c in cb.js('inspect', *ids) if ids else []:
            for bindings in (c['NetworkSettings'].get('Ports') or {}).values():
                if any(int(b['HostPort']) == port for b in bindings or []):
                    raise ValueError('Port already published by Docker')


def select_port(preferred=8080, automatic=False, app='nginx'):
    if not automatic:
        preflight(preferred, app=app)
        return preferred
    if not 1024 <= preferred <= 65535:
        raise ValueError('Port must be 1024-65535')
    for port in range(preferred, min(preferred + 20, 65536)):
        try:
            preflight(port, app=app)
            return port
        except OSError as error:
            import errno
            if error.errno != errno.EADDRINUSE:
                raise
        except ValueError as error:
            if str(error) != 'Port already published by Docker':
                raise
    raise ValueError('No free localhost port in the bounded 20-port range')


def reinstall(registry, record, port, automatic):
    """Reuse only a fully owned, uninstalled volume. Never pull or migrate its data."""
    if record['market']['state'] != 'uninstalled' or resources(record):
        raise ValueError('Reinstall requires uninstalled state and no existing containers')
    volume = record['project'] + '_data'
    if volume not in cb.docker('volume', 'ls', '-q').decode().split():
        raise ValueError('Retained data volume missing; refusing to create replacement')
    image = record['market']['image']
    if cb.js('image', 'inspect', image)[0]['Id'] != image:
        raise ValueError('Retained image identity mismatch')
    original = json.loads(json.dumps(record))
    # A retained host mapping reserves its upstream identity logically. Never
    # silently route it to a different port during reinstall.
    if 'domain' in record['market']:
        market_domain.owned(record)
        if automatic or (port is not None and port != record['market']['port']):
            raise ValueError('Remove domain mapping before changing its retained upstream port or using --auto-port')
    record['market']['port'] = select_port(record['market']['port'] if port is None else port, automatic, app=record['market']['app'])
    try:
        write_compose(record)
        up(record)
        record['market']['state'] = 'healthy'
        save(registry, record)
    except BaseException:
        # The preflight proved this namespace empty. Revalidate labels before cleanup.
        # No volume is removed. Writable apps may have committed data; no data rollback is claimed.
        try:
            for container in resources(record):
                cb.docker('stop', container['Id'])
                cb.docker('rm', container['Id'])
        except BaseException:
            raise RuntimeError('Reinstall failed and container cleanup failed; original registry/config/data retained; inspect owned resources before retry') from None
        finally:
            write_compose(original)
        raise RuntimeError('Reinstall failed; newly created containers removed; original registry/config/data retained') from None
    if 'domain' in record['market']:
        mapping = record['market']['domain']
        market_domain.change(registry, record, mapping['name'], mapping['listen'])
    print('Reinstall completed; healthy; localhost port ' + str(record['market']['port']))


def pull(app='nginx'):
    image = metadata(app)['image']
    cb.docker('pull', image)
    return cb.js('image', 'inspect', image)[0]['Id']


def up(record):
    wait_timeout = 45
    app = record.get('market', {}).get('app')
    if app:
        wait_timeout = 45 + metadata(app).get('health_retries', 10) * 2
    cb.docker('compose', '-p', record['project'], '-f', record['compose'],
              'up', '-d', '--wait', '--wait-timeout', str(wait_timeout), '--pull', 'never')
    if health(record) != 'healthy':
        raise RuntimeError('Application health check failed')


def health(record):
    containers = resources(record)
    if not containers:
        return 'absent; data/config retained'
    state = containers[0]['State']
    if not state['Running']:
        return 'stopped'
    status = state.get('Health', {}).get('Status', 'unknown')
    spec = metadata(record['market']['app'])
    if status == 'healthy' and spec.get('health_json'):
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open('http://127.0.0.1:%s%s' % (record['market']['port'], spec['health_json']), timeout=3) as response:
                if response.status != 200 or json.loads(response.read(4096)).get('healthy') is not True:
                    return 'unhealthy'
        except Exception:
            return 'unhealthy'
    return status


def operate(action, app='nginx', port=None, accepted=False, project=None, automatic=False, reuse=False, domain=None, listen=80, tls=None):
    spec = metadata(app)
    if action not in ('install', 'reinstall', 'status', 'update', 'uninstall', 'domain', 'tls', 'tls-refresh'):
        raise ValueError('Unsupported managed action')
    if action in ('domain', 'tls', 'tls-refresh') and not spec['domain']:
        raise ValueError('Domain/TLS unsupported for this application; localhost only')
    project = project or 'fb-market-' + app
    if action != 'status' and not accepted:
        raise ValueError('Explicit --confirm required (update/uninstall cause downtime; data retained)')
    with cb.lock(project) as registry:
        if action == 'install':
            compose = cb.BASE / (project + '.compose.json')
            if registry.exists() or registry.is_symlink() or compose.exists() or compose.is_symlink():
                raise ValueError('Existing registry/configuration; refusing adoption')
            port = select_port(spec['port'] if port is None else port, automatic, app=app)
            if (cb.docker('ps', '-aq', '--filter', 'name=^/' + project + '-app$').strip() or
                    cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip() or
                    project + '_data' in cb.docker('volume', 'ls', '-q').decode().split()):
                raise ValueError('Existing unmanaged Docker resources; refusing adoption')
            record = {'owner': cb.OWNER, 'project': project, 'compose': str(compose.absolute()),
                      'market': {'owner': OWNER, 'app': app, 'token': uuid.uuid4().hex,
                                 'port': port, 'image': pull(app), 'state': 'installing'}}
            write_compose(record)
            save(registry, record)
            try:
                up(record)
            except BaseException:
                record['market']['state'] = 'install-failed'
                save(registry, record)
                raise RuntimeError('Install failed; private registry/config and any created resources retained; inspect status then confirmed uninstall') from None
        else:
            if not registry.exists():
                raise ValueError('Not managed; legacy/native/unknown installations are never adopted')
            record = load(registry, project)
            if record['market']['app'] != app:
                raise ValueError('Registered application identity mismatch')
            if action != 'status' and (cb.BASE / (project + '.domain-recovery.json')).exists():
                raise ValueError('Pending domain recovery journal; manual recovery required')
            if action not in ('status', 'tls-refresh') and (cb.BASE / (project + '.tls-refresh.json')).exists():
                raise ValueError('Pending TLS refresh; repair supplied files and retry tls-refresh --confirm')
            if 'domain' in record['market']:
                market_domain.owned(record)
            if action == 'tls-refresh':
                market_domain.refresh(registry, record)
                return
            if action == 'reinstall':
                if not reuse:
                    raise ValueError('Explicit --reuse-data required for retained content')
                reinstall(registry, record, port, automatic)
                return
            containers = resources(record)
            if action == 'status':
                print('managed-compose', app, record['market']['state'], health(record),
                      'http://127.0.0.1:' + str(record['market']['port']))
                market_domain.status(record)
                if record['market']['state'] == 'uninstalled':
                    print('Retained data: reinstall ' + app + ' --confirm --reuse-data [--auto-port]')
                return
            if action == 'tls':
                mapping = record['market'].get('domain')
                if not mapping:
                    raise ValueError('Create an owned domain mapping first')
                if tls is not None and (record['market']['state'] != 'healthy' or health(record) != 'healthy'):
                    raise ValueError('TLS activation requires healthy managed app')
                market_domain.change(registry, record, mapping['name'], mapping['listen'], mapping['enabled'], tls=tls)
                return
            if action == 'domain':
                if domain and (record['market']['state'] != 'healthy' or health(record) != 'healthy'):
                    raise ValueError('Domain activation requires healthy managed app')
                market_domain.change(registry, record, domain, listen)
                return
            if action == 'uninstall':
                if 'domain' in record['market']:
                    mapping = record['market']['domain']
                    market_domain.change(registry, record, mapping['name'], mapping['listen'], enabled=False)
                    record = load(registry, project)
                for c in containers:
                    cb.docker('stop', c['Id'])
                    cb.docker('rm', c['Id'])
                record['market']['state'] = 'uninstalled'
                save(registry, record)
                print('Uninstalled; named data volume, registry and configuration retained')
                return
            if record['market']['state'] != 'healthy' or health(record) != 'healthy':
                raise ValueError('Update requires healthy managed app; manual recovery required')
            # Reject drift in mounts, Compose identity and shared storage before recreation.
            cb.inspect(record)
            preflight(record['market']['port'], False, app=app)
            candidate = pull(app)
            if candidate == record['market']['image']:
                print('Already using current catalog image')
                return
            if not spec['readonly']:
                raise ValueError('Image upgrade refused: writable database migration/rollback unsupported; retained image and data unchanged')
            # Nginx serves the data mount read-only: update cannot migrate or rewrite content.
            recovery = cb.BASE / (project + '.previous.json')
            cb.no_links(recovery)
            save(recovery, record)
            previous = record['market']['image']
            record['market']['image'] = candidate
            record['market']['state'] = 'updating'
            save(registry, record)
            write_compose(record)
            try:
                up(record)
            except BaseException:
                record['market']['image'] = previous
                write_compose(record)
                try:
                    up(record)
                except BaseException:
                    record['market']['state'] = 'recovery-required'
                    save(registry, record)
                    raise RuntimeError('Update AND rollback failed; data and previous image record retained; manual recovery required') from None
                record['market']['state'] = 'healthy'
                save(registry, record)
                raise RuntimeError('Update failed; previous image restored; recovery record retained') from None
        record['market']['state'] = 'healthy'
        save(registry, record)
        print(action.capitalize() + ' completed; healthy; localhost port ' + str(record['market']['port']))


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('catalog', 'install', 'reinstall', 'status', 'update', 'uninstall', 'domain', 'tls', 'tls-refresh'))
    p.add_argument('app', nargs='?', default='nginx', choices=tuple(CATALOG))
    p.add_argument('--port', type=int, help='Preferred port; catalog default (nginx 8080, ntfy 8081) or retained port for reinstall')
    p.add_argument('--auto-port', action='store_true', help='Probe at most 20 localhost ports; not a reservation')
    p.add_argument('--reuse-data', action='store_true', help='Explicitly reuse owned retained data on reinstall')
    p.add_argument('--confirm', action='store_true')
    p.add_argument('--domain', help='Managed HTTP-only DNS name (domain action)')
    p.add_argument('--listen', type=int, default=80, help='Host HTTP port for domain mapping')
    p.add_argument('--remove-domain', action='store_true', help='Remove the owned domain mapping')
    p.add_argument('--cert', help='Existing PEM certificate/fullchain; no issuance')
    p.add_argument('--key', help='Existing unencrypted PEM key, operator-owned mode 0600/0400')
    p.add_argument('--tls-port', type=int, default=443)
    p.add_argument('--no-redirect', action='store_true', help='Explicitly retain HTTP service alongside HTTPS')
    p.add_argument('--disable-tls', action='store_true')
    args = p.parse_args()
    if args.action == 'tls':
        if args.disable_tls:
            if args.cert or args.key or args.no_redirect or args.tls_port != 443:
                p.error('--disable-tls cannot include certificate/port/redirect options')
        elif not (args.cert and args.key):
            p.error('TLS requires both --cert and --key, or --disable-tls')
    elif args.cert or args.key or args.disable_tls or args.no_redirect or args.tls_port != 443:
        p.error('TLS options apply only to tls action')
    if args.action == 'catalog':
        for app in CATALOG:
            spec = metadata(app)
            print('%s: %s; image=%s; localhost port %s; RAM limit %s / CPU 0.50 / PIDs 64; %s MiB minimum free disk (not a quota); Docker Compose v2/Python 3/Linux required' %
                  (app, spec['description'], spec['image'], spec['port'], spec['memory'], spec['bytes'] // 1024 // 1024))
        return
    if (args.auto_port or args.port is not None) and args.action not in ('install', 'reinstall'):
        p.error('Port options apply only to install/reinstall')
    if args.reuse_data and args.action != 'reinstall':
        p.error('--reuse-data applies only to reinstall')
    if args.action == 'domain' and not args.confirm:
        p.error('Domain mapping requires explicit --confirm')
    if args.action != 'domain' and (args.domain or args.remove_domain):
        p.error('--domain/--remove-domain apply only to domain')
    if args.action == 'domain' and (args.domain is None) == (not args.remove_domain):
        p.error('Choose exactly one of --domain NAME or --remove-domain')
    operate(args.action, args.app, args.port, args.confirm, automatic=args.auto_port, reuse=args.reuse_data,
            domain=None if args.remove_domain else args.domain, listen=args.listen,
            tls={'cert': args.cert, 'key': args.key, 'listen': args.tls_port, 'redirect': not args.no_redirect}
            if args.action == 'tls' and not args.disable_tls else None)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Managed market failed:', error, file=sys.stderr)
        sys.exit(1)
