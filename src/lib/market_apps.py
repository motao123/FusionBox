"""Small opt-in managed catalog. Never imports or executes legacy installer metadata."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import uuid
import urllib.request


import compose_backup as cb
from backup_jobs import atomic
import market_domain
import market_catalog

OWNER = 'fusionbox-market-v1'
RUNTIME_CATALOG = None
CATALOG_SOURCE = 'legacy-builtin'
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
                 'user': '0:0', 'health_retries': 60,
                 'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:5244/ || exit 1'],
                 'domain': False,
                 'description': 'OpenList file list program with WebDAV (Alist fork); admin password via container CLI; runs as root with all capabilities dropped (writable volume); localhost only; no domain/TLS; image upgrades refused'},
    'navidrome': {'image': 'deluan/navidrome:latest@sha256:a384948b81bd1529986c5960169e7fc4fa00f46bde6bd517971a4c36671db2af',
                  'port': 8089, 'bytes': 1024 * 1024 * 1024, 'target': 4533,
                  'mounts': [{'suffix': 'data', 'dest': '/data', 'readonly': False},
                             {'suffix': 'music', 'dest': '/music', 'readonly': True}],
                  'memory': '256m',
                  'health': ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:4533/ || exit 1'],
                  'domain': False,
                  'description': 'Navidrome music streaming server; copy audio files into the music named volume (docker cp); localhost only; no domain/TLS; image upgrades refused'},
}


def configure_catalog(url=None, sha256=None, revision=None):
    """Load the built-in or pinned remote declarative catalog for this invocation."""
    global RUNTIME_CATALOG, CATALOG_SOURCE
    RUNTIME_CATALOG, CATALOG_SOURCE = market_catalog.load(cb.BASE, url, sha256, revision)
    return CATALOG_SOURCE


def catalog_apps():
    apps = dict(CATALOG)
    if RUNTIME_CATALOG is not None:
        overlap = set(apps).intersection(RUNTIME_CATALOG['apps'])
        if overlap:
            raise ValueError('Declarative catalog application collides with built-in ID: ' + sorted(overlap)[0])
        apps.update(RUNTIME_CATALOG['apps'])
    return apps


def is_manifest(spec):
    return isinstance(spec, dict) and 'services' in spec


def app_spec(app):
    apps = catalog_apps()
    if app not in apps:
        raise ValueError('Unsupported managed application')
    spec = apps[app]
    if is_manifest(spec):
        return spec
    return metadata(app)


def record_spec(record):
    stored = record.get('market', {}).get('catalog_app')
    if stored is None:
        return metadata(record['market']['app'])
    if not is_manifest(stored) or market_catalog.app_digest(stored) != record['market'].get('catalog_digest'):
        raise ValueError('Managed catalog application snapshot changed')
    return stored


def manifest_ports(spec):
    return [(service, port) for service in spec['services'] for port in service['ports']]


def resolve_bind(source, nas_path):
    if '{nas_path}' not in source:
        return source
    if nas_path is None:
        raise ValueError('Application requires explicit --nas-path')
    if (not isinstance(nas_path, str) or not nas_path.startswith('/') or '..' in Path(nas_path).parts or
            not re.fullmatch(r'/[A-Za-z0-9_. /-]+', nas_path)):
        raise ValueError('NAS path must be a safe absolute path')
    return source.replace('{nas_path}', nas_path)


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


def manifest_document(record):
    spec = record_spec(record)
    labels = {'io.fusionbox.market': record['market']['token']}
    project = record['project']
    result = {'services': {}, 'volumes': {}}
    for item in spec['services']:
        service = {
            'image': item['image'], 'container_name': project + '-' + item['id'],
            'restart': 'unless-stopped',
            'labels': labels, 'mem_limit': item['memory'], 'cpus': item['cpus'],
            'pids_limit': item['pids_limit'],
            'logging': {'driver': 'json-file', 'options': {'max-size': '5m', 'max-file': '2'}},
            'healthcheck': {'test': item['health'], 'interval': '2s', 'timeout': '2s',
                            'retries': item['health_retries']}}
        # Catalog `bridge` means "this application's own private network": emitting
        # the literal `bridge` would attach every service to Docker's global default
        # bridge, where service names do not resolve and a multi-container app
        # cannot reach its own database. Only `host` is passed through verbatim.
        if item['network_mode'] == 'host':
            service['network_mode'] = 'host'
        if item['ports']:
            service['ports'] = ['127.0.0.1:%s:%s/%s' % (p['published'], p['target'], p['protocol'])
                                for p in item['ports']]
        volumes = []
        for volume in item['volumes']:
            volumes.append(volume['name'] + ':' + volume['target'] + (':ro' if volume['read_only'] else ''))
            result['volumes'][volume['name']] = {'name': project + '_' + volume['name'], 'labels': labels}
        for bind in item['binds']:
            source = resolve_bind(bind['source'], record['market'].get('nas_path'))
            volumes.append(source + ':' + bind['target'] + (':ro' if bind['read_only'] else ''))
        if item['docker_socket']:
            volumes.append('/var/run/docker.sock:/var/run/docker.sock')
        if volumes:
            service['volumes'] = volumes
        if item['devices']:
            service['devices'] = ['%s:%s:%s' % (d['source'], d['target'], d['permissions']) for d in item['devices']]
        for field in ('command', 'entrypoint', 'environment', 'user'):
            if field in item:
                service[field] = item[field].copy() if isinstance(item[field], (list, dict)) else item[field]
        # Every declared service carries a healthcheck (schema requires it), so a
        # dependency can always gate on actual readiness instead of mere start.
        if item.get('depends_on'):
            service['depends_on'] = {dep: {'condition': 'service_healthy'} for dep in item['depends_on']}
        for field in ('shm_size', 'sysctls'):
            if field in item:
                service[field] = item[field].copy() if isinstance(item[field], dict) else item[field]
        if item.get('tmpfs'):
            service['tmpfs'] = list(item['tmpfs'])
        if item.get('read_only'):
            service['read_only'] = True
        if not spec['high_privilege']:
            service.update(init=True, cap_drop=['ALL'], security_opt=['no-new-privileges:true'])
        result['services'][item['id']] = service
    if not result['volumes']:
        del result['volumes']
    return result


def document(record, image=None):
    spec = record_spec(record)
    if is_manifest(spec):
        if image is not None:
            raise ValueError('Per-image override unsupported for declarative multi-service applications')
        return manifest_document(record)
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
        service['user'] = spec['user']
        if 'command' in spec:
            service['command'] = spec['command']
        service.update(init=True, cap_drop=['ALL'], security_opt=['no-new-privileges:true'])
    return result


def save(path, record):
    atomic(path, json.dumps(record) + '\n')


def _memory_bytes(value):
    """Convert a validated `<n>m` catalog size into bytes for Docker API comparison."""
    if not re.fullmatch(r'[1-9][0-9]*m', value or ''):
        raise ValueError('Invalid catalog size: ' + str(value))
    return int(value[:-1]) * 1024 * 1024


def write_compose(record, image=None):
    atomic(Path(record['compose']), json.dumps(document(record, image)) + '\n')


def load(path, project):
    record = cb.load(path, project)
    m = record.get('market', {})
    declarative = 'catalog_app' in m
    known = m.get('app') in CATALOG if not declarative else is_manifest(m.get('catalog_app'))
    valid_image = (re.fullmatch('sha256:[a-f0-9]{64}', m.get('image', '')) is not None) if not declarative else 'image' not in m
    valid_port = (type(m.get('port')) is int and 1024 <= m['port'] <= 65535) if not declarative else 'port' not in m
    if (m.get('owner') != OWNER or not known or
            not re.fullmatch('[a-f0-9]{32}', m.get('token', '')) or not valid_image or not valid_port or
            record['compose'] != str((cb.BASE / (project + '.compose.json')).absolute())):
        raise ValueError('Unknown managed application ownership/type')
    if declarative:
        record_spec(record)
    cb.no_links(Path(record['compose']))
    if json.loads(Path(record['compose']).read_text()) != document(record):
        raise ValueError('Managed Compose configuration changed; manual recovery required')
    return record


def manifest_resources(record):
    """Validate every declarative container and named volume against the stored snapshot."""
    project, token = record['project'], record['market']['token']
    spec = record_spec(record)
    ids = cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).decode().split()
    expected_names = {project + '-' + service['id']: service for service in spec['services']}
    named = []
    for name in expected_names:
        named.extend(cb.docker('ps', '-aq', '--filter', 'name=^/' + name + '$').decode().split())
    if set(ids) != set(named) or len(ids) > len(expected_names):
        raise ValueError('Unknown container ownership')
    containers = cb.js('inspect', *ids) if ids else []
    for container in containers:
        name = container['Name'].lstrip('/')
        service = expected_names.get(name)
        labels = container['Config'].get('Labels') or {}
        # `bridge` in the catalog means the application-private compose network,
        # so the expected runtime network is the project network, not `bridge`.
        expected_network = 'host' if service and service['network_mode'] == 'host' else project + '_default'
        if (service is None or labels.get('io.fusionbox.market') != token or
                labels.get('com.docker.compose.service') != service['id'] or
                labels.get('com.docker.compose.project.config_files') != record['compose'] or
                container['HostConfig'].get('NetworkMode') != expected_network or
                container['HostConfig'].get('Privileged')):
            raise ValueError('Unknown container ownership/type')
        expected_mounts = {(project + '_' + v['name'], v['target'], not v['read_only']) for v in service['volumes']}
        actual_mounts = {(mount.get('Name'), mount.get('Destination'), mount['RW'])
                         for mount in container.get('Mounts', []) if mount['Type'] == 'volume'}
        if actual_mounts != expected_mounts:
            raise ValueError('Unexpected application storage')
        socket_mounts = [m for m in container.get('Mounts', []) if m.get('Destination') == '/var/run/docker.sock']
        if bool(socket_mounts) != service['docker_socket']:
            raise ValueError('Unexpected Docker socket capability')
        # The declared multi-container capabilities must be the ones actually in
        # force; a silent drop would mean the app runs without what it declared.
        host = container['HostConfig']
        if service.get('shm_size') and host.get('ShmSize') != _memory_bytes(service['shm_size']):
            raise ValueError('Unexpected shared memory size')
        if (host.get('Sysctls') or {}) != (service.get('sysctls') or {}):
            raise ValueError('Unexpected sysctls')
        if bool(host.get('ReadonlyRootfs')) != bool(service.get('read_only')):
            raise ValueError('Unexpected root filesystem mode')
        if set((host.get('Tmpfs') or {}).keys()) != set(service.get('tmpfs') or []):
            raise ValueError('Unexpected tmpfs mounts')
        if service.get('entrypoint') is not None and container['Config'].get('Entrypoint') != service['entrypoint']:
            raise ValueError('Unexpected container entrypoint')
    volumes = cb.docker('volume', 'ls', '-q').decode().split()
    names = {v['name'] for service in spec['services'] for v in service['volumes']}
    for suffix in names:
        name = project + '_' + suffix
        if name in volumes:
            volume = cb.js('volume', 'inspect', name)[0]
            labels = volume.get('Labels') or {}
            if (labels.get('io.fusionbox.market') != token or labels.get('com.docker.compose.project') != project or
                    volume['Driver'] != 'local' or volume.get('Options')):
                raise ValueError('Unknown data volume ownership')
            users = cb.docker('ps', '-aq', '--filter', 'volume=' + name).decode().split()
            if set(users) - set(ids):
                raise ValueError('Data volume shared outside managed app')
        elif containers:
            raise ValueError('Managed data volume missing')
    return containers


def resources(record):
    """Check exact resource names and labels before any stop/remove/recreate."""
    if is_manifest(record_spec(record)):
        return manifest_resources(record)
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


_COMPOSE_HINT = ('受管应用市场需要 Docker Compose v2（docker compose 子命令）。\n'
                 '  安装 Docker: curl -fsSL https://get.docker.com | sh\n'
                 '  安装 compose 插件: apt-get install -y docker-compose-plugin'
                 '（或 yum install -y docker-compose-plugin）')


def docker_preflight():
    """Explain missing Docker/Compose in Chinese before any docker call runs.

    This runs before the secret-withholding docker wrapper is used, so it can be
    explicit about the cause; ``output withheld`` must stay reserved for real
    docker operations that may echo credentials.
    """
    if shutil.which('docker') is None:
        raise ValueError('受管应用市场需要 Docker：未检测到 docker 命令。\n'
                         '  安装: curl -fsSL https://get.docker.com | sh')
    probe = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', 'info'],
                           capture_output=True)
    if probe.returncode:
        raise ValueError('Docker 守护进程不可用。\n'
                         '  请检查: systemctl status docker（或 service docker status）')
    probe = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock', 'compose', 'version'],
                           capture_output=True)
    if probe.returncode:
        raise ValueError(_COMPOSE_HINT)


def preflight(port, check_port=True, app='nginx'):
    if type(port) is not int or not 1024 <= port <= 65535:
        raise ValueError('Port must be 1024-65535')
    cb.docker('compose', 'version')
    root = Path(cb.js('info', '--format', '{{json .DockerRootDir}}'))
    spec = app_spec(app)
    required = spec['bytes']
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


def pull_manifest(spec):
    images = {}
    for service in spec['services']:
        image = service['image']
        if image in images:
            continue
        cb.docker('pull', image)
        identity = cb.js('image', 'inspect', image)[0]['Id']
        if not re.fullmatch(r'sha256:[a-f0-9]{64}', identity):
            raise ValueError('Invalid pulled image identity')
        images[image] = identity
    return images


def pull(app='nginx'):
    spec = app_spec(app)
    if is_manifest(spec):
        return pull_manifest(spec)
    image = metadata(app)['image']
    cb.docker('pull', image)
    return cb.js('image', 'inspect', image)[0]['Id']


def up(record):
    wait_timeout = 45
    if record.get('market'):
        spec = record_spec(record)
        if is_manifest(spec):
            wait_timeout += max(service['health_retries'] for service in spec['services']) * 2
        else:
            wait_timeout += spec.get('health_retries', 10) * 2
    cb.docker('compose', '-p', record['project'], '-f', record['compose'],
              'up', '-d', '--wait', '--wait-timeout', str(wait_timeout), '--pull', 'never')
    if health(record) != 'healthy':
        raise RuntimeError('Application health check failed')


def health(record):
    containers = resources(record)
    if not containers:
        return 'absent; data/config retained'
    states = [container['State'] for container in containers]
    if any(not state['Running'] for state in states):
        return 'stopped'
    statuses = [state.get('Health', {}).get('Status', 'unknown') for state in states]
    status = 'healthy' if all(value == 'healthy' for value in statuses) else next(value for value in statuses if value != 'healthy')
    spec = record_spec(record)
    if is_manifest(spec):
        return status
    if status == 'healthy' and spec.get('health_json'):
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open('http://127.0.0.1:%s%s' % (record['market']['port'], spec['health_json']), timeout=3) as response:
                if response.status != 200 or json.loads(response.read(4096)).get('healthy') is not True:
                    return 'unhealthy'
        except Exception:
            return 'unhealthy'
    return status


def manifest_shape(spec):
    """Per-service fields whose change moves data or changes reachability.

    Deliberately excludes image/health/command/environment/memory: those are what
    an update is allowed to change. Anything else (service set, storage, published
    ports, network mode, binds, devices, socket) is a migration, not an update.
    """
    return {service['id']: {key: service.get(key) for key in
                            ('volumes', 'ports', 'network_mode', 'binds', 'devices', 'docker_socket', 'user')}
            for service in spec['services']}


def manifest_target(record):
    """Copy of the catalog spec for this app, refusing any structural change."""
    stored = record_spec(record)
    live = catalog_apps().get(record['market']['app'])
    if live is None:
        raise ValueError('Application is no longer in the catalog; keep the pinned snapshot or uninstall')
    if not is_manifest(live):
        raise ValueError('Catalog entry type changed; refusing in-place update')
    if manifest_shape(live) != manifest_shape(stored):
        raise ValueError('Service topology, storage or published ports changed in the catalog; '
                         'in-place update would move data or change reachability. Uninstall, then install.')
    return json.loads(json.dumps(live))


def manifest_images(record, target, overrides):
    """Resolve each service image (explicit override wins) and return the changed ones."""
    stored = {service['id']: service['image'] for service in record_spec(record)['services']}
    unknown = sorted(set(overrides) - set(stored))
    if unknown:
        raise ValueError('Unknown service for --service-image: ' + unknown[0])
    changed = {}
    for service in target['services']:
        image = overrides.get(service['id'], service['image'])
        if not market_catalog.IMAGE.fullmatch(image):
            raise ValueError('Service image must be digest-pinned: ' + image)
        service['image'] = image
        if image != stored[service['id']]:
            changed[service['id']] = image
    return changed


def ensure_images(images):
    """Pull only images that are not present locally (all are digest-pinned)."""
    for image in images:
        try:
            cb.js('image', 'inspect', image)
        except Exception:  # noqa: BLE001 - absent image is the expected pull trigger
            cb.docker('pull', image)


def manifest_update(registry, record, overrides):
    """Replace service images of a healthy declarative app as one transaction."""
    target = manifest_target(record)
    if record['market']['state'] != 'healthy' or health(record) != 'healthy':
        raise ValueError('Update requires a healthy managed application; manual recovery required')
    changed = manifest_images(record, target, dict(overrides or {}))
    if not changed:
        print('No image change requested; nothing to do. Use --service-image SERVICE=IMAGE@sha256:...')
        return
    ensure_images(sorted(set(changed.values())))
    journal = cb.BASE / (record['project'] + '.update.json')
    cb.no_links(journal)
    original = json.loads(json.dumps(record))
    save(journal, original)
    record['market']['catalog_app'] = target
    record['market']['catalog_digest'] = market_catalog.app_digest(target)
    record['market']['catalog_revision'] = (RUNTIME_CATALOG or {}).get('revision', record['market'].get('catalog_revision'))
    record['market']['catalog_source'] = CATALOG_SOURCE
    record['market']['state'] = 'updating'
    save(registry, record)
    try:
        write_compose(record)
        up(record)
    except BaseException:
        save(registry, original)
        try:
            write_compose(original)
            up(original)
        except BaseException:
            original['market']['state'] = 'recovery-required'
            save(registry, original)
            raise RuntimeError('Update AND rollback failed; recovery journal ' + str(journal) +
                               ' retained; data volumes untouched; manual recovery required') from None
        journal.unlink(missing_ok=True)
        raise RuntimeError('Update failed; previous images and configuration restored') from None
    record['market']['state'] = 'healthy'
    save(registry, record)
    journal.unlink(missing_ok=True)
    print('Update completed; healthy; changed services: ' + ', '.join(sorted(changed)))


def manifest_reinstall(registry, record):
    """Recreate a retained declarative application from its pinned snapshot."""
    if record['market']['state'] != 'uninstalled':
        raise ValueError('Reinstall requires uninstalled state and no running containers')
    if resources(record):
        raise ValueError('Reinstall requires no existing containers')
    spec = record_spec(record)
    expected = {record['project'] + '_' + volume['name'] for service in spec['services'] for volume in service['volumes']}
    missing = sorted(expected - set(cb.docker('volume', 'ls', '-q').decode().split()))
    if missing:
        raise ValueError('Retained data volume missing; refusing to create a replacement: ' + missing[0])
    ensure_images(sorted({service['image'] for service in spec['services']}))
    try:
        write_compose(record)
        up(record)
        record['market']['state'] = 'healthy'
        save(registry, record)
    except BaseException:
        try:
            for container in resources(record):
                cb.docker('stop', container['Id'])
                cb.docker('rm', container['Id'])
        except BaseException:
            raise RuntimeError('Reinstall failed and container cleanup failed; registry/config/data retained; '
                               'inspect owned resources before retry') from None
        raise RuntimeError('Reinstall failed; newly created containers removed; original registry/config/data retained') from None
    print('Reinstall completed; healthy')


def operate(action, app='nginx', port=None, accepted=False, project=None, automatic=False, reuse=False,
            domain=None, listen=80, tls=None, risk_ack=None, nas_path=None, images=None):
    if action not in ('install', 'reinstall', 'status', 'update', 'uninstall', 'domain', 'tls', 'tls-refresh'):
        raise ValueError('Unsupported managed action')
    # catalog needs no docker at all; everything else touches the daemon.
    if action != 'catalog':
        docker_preflight()
    project = project or 'fb-market-' + app
    spec = manifest = None
    if action == 'install':
        spec = app_spec(app)
        manifest = is_manifest(spec)
        if manifest and port is not None:
            raise ValueError('Declarative catalog ports are fixed by the pinned manifest')
        if manifest and automatic:
            raise ValueError('--auto-port is unsupported for declarative catalog applications')
        if manifest and spec['revoked']:
            raise ValueError('Application is revoked and cannot be installed')
        if manifest and spec['nas_path'] != (nas_path is not None):
            raise ValueError('NAS application requires exactly one explicit --nas-path')
        if manifest and spec['high_privilege'] and risk_ack != spec['risk_acknowledgement']:
            raise ValueError('HIGH PRIVILEGE application requires exact --risk-ack text: ' + spec['risk_acknowledgement'])
    if action != 'status' and not accepted:
        raise ValueError('Explicit --confirm required (update/uninstall cause downtime; data retained)')
    with cb.lock(project) as registry:
        if action == 'install':
            compose = cb.BASE / (project + '.compose.json')
            if registry.exists() or registry.is_symlink() or compose.exists() or compose.is_symlink():
                raise ValueError('Existing registry/configuration; refusing adoption')
            if manifest:
                for service, binding in manifest_ports(spec):
                    preflight(binding['published'], app=app)
                existing_names = [project + '-' + service['id'] for service in spec['services']]
                volume_names = {project + '_' + volume['name'] for service in spec['services'] for volume in service['volumes']}
                if (cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip() or
                        any(cb.docker('ps', '-aq', '--filter', 'name=^/' + name + '$').strip() for name in existing_names) or
                        volume_names.intersection(cb.docker('volume', 'ls', '-q').decode().split())):
                    raise ValueError('Existing unmanaged Docker resources; refusing adoption')
                pull_manifest(spec)
                market = {'owner': OWNER, 'app': app, 'token': uuid.uuid4().hex, 'state': 'installing',
                          'catalog_schema': RUNTIME_CATALOG['schema_version'],
                          'catalog_id': RUNTIME_CATALOG['catalog_id'], 'catalog_revision': RUNTIME_CATALOG['revision'],
                          'catalog_source': CATALOG_SOURCE, 'catalog_app': spec,
                          'catalog_digest': market_catalog.app_digest(spec)}
                if nas_path is not None:
                    market['nas_path'] = nas_path
                record = {'owner': cb.OWNER, 'project': project, 'compose': str(compose.absolute()), 'market': market}
            else:
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
            spec = record_spec(record)
            manifest = is_manifest(spec)
            if action in ('domain', 'tls', 'tls-refresh') and not spec['domain']:
                raise ValueError('Domain/TLS unsupported for this application; localhost only')
            if manifest and action in ('reinstall', 'update'):
                if action == 'update':
                    manifest_update(registry, record, images)
                else:
                    if not reuse:
                        raise ValueError('Explicit --reuse-data required for retained content')
                    manifest_reinstall(registry, record)
                return
            if action != 'status' and (cb.BASE / (project + '.domain-recovery.json')).exists():
                raise ValueError('Pending domain recovery journal; manual recovery required')
            if action not in ('status', 'tls-refresh') and (cb.BASE / (project + '.tls-refresh.json')).exists():
                raise ValueError('Pending TLS refresh; repair supplied files and retry tls-refresh --confirm')
            if (manifest and action not in ('status', 'uninstall') and
                    (cb.BASE / (project + '.update.json')).exists()):
                raise ValueError('Pending declarative update journal; the previous update failed. '
                                 'Inspect status, recover manually if needed, then remove ' +
                                 str(cb.BASE / (project + '.update.json')))
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
                location = ('http://127.0.0.1:' + str(record['market']['port'])) if not manifest else 'localhost bindings from pinned catalog'
                print('managed-compose', app, record['market']['state'], health(record), location)
                market_domain.status(record)
                if record['market']['state'] == 'uninstalled' and not manifest:
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
        if manifest:
            ports = ', '.join('127.0.0.1:%s/%s' % (p['published'], p['protocol']) for _, p in manifest_ports(spec))
            print(action.capitalize() + ' completed; healthy; localhost only: ' + (ports or 'host network'))
        else:
            print(action.capitalize() + ' completed; healthy; localhost port ' + str(record['market']['port']))


HELP_TEXT = """受管应用生命周期

用法: fusionbox market managed <操作> [应用] [选项]

操作:
  catalog                    查看受管目录（应用 ID、端口、资源限制）
  status <应用>              查看本地证书校验与入口状态
  install <应用> --confirm   安装（默认 localhost）
  reinstall <应用> --confirm --reuse-data   复用保留数据重装
  update <应用> --confirm    更新（单服务：镜像升级默认拒绝；多服务：按服务换镜像并事务化回滚）
  uninstall <应用> --confirm 卸载（保留具名卷数据）
  domain <应用> --domain <域名> --confirm    绑定自有域名（HTTP）
  tls <应用> --cert <证书> --key <私钥> --confirm   使用已有 PEM
  tls-refresh <应用> --confirm    校验并重载已更新的 PEM

常用选项:
  --port <端口>   首选 localhost 端口
  --auto-port     占用时最多探测后续 20 个端口（不保证预留）
  --nas-path <路径>  目录模板所需的宿主 NAS 根路径
  --risk-ack <文本>  高权限应用要求的完整确认文本
  --service-image <服务>=<镜像@sha256:...>   多服务应用按服务换镜像（可重复；仅 update）

多服务（声明式目录）说明: 只支持 install/status/update/reinstall/uninstall；
update 不接受改动服务集合、卷、发布端口或网络模式的目录变更（那属于迁移），
显式改镜像用 --service-image，失败会自动回滚到上一组镜像。

示例: fusionbox market managed install nginx --confirm
      fusionbox market managed catalog
"""


class _ChineseArgumentParser(argparse.ArgumentParser):
    """Print a Chinese menu on missing/invalid arguments, never a raw traceback."""

    def error(self, message):
        print('参数有误: ' + message, file=sys.stderr)
        print(HELP_TEXT, file=sys.stderr)
        raise SystemExit(2)


def main(argv=None):
    os.umask(0o077)
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] in ('help', '--help', '-h'):
        print(HELP_TEXT)
        return
    p = _ChineseArgumentParser(description=__doc__)
    p.add_argument('action', choices=('catalog', 'install', 'reinstall', 'status', 'update', 'uninstall', 'domain', 'tls', 'tls-refresh'))
    p.add_argument('app', nargs='?', default='nginx')
    p.add_argument('--catalog-url', help='HTTPS JSON catalog URL; requires a content or revision pin')
    p.add_argument('--catalog-sha256', help='Expected remote catalog content SHA256')
    p.add_argument('--catalog-revision', help='Expected catalog commit/revision identifier')
    p.add_argument('--risk-ack', help='Exact acknowledgement printed for high-privilege applications')
    p.add_argument('--nas-path', help='Absolute host NAS root for catalog bind templates')
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
    p.add_argument('--service-image', action='append', default=[], metavar='SERVICE=IMAGE@sha256:...',
                   help='Declarative catalog update: replace one service image (repeatable)')
    args = p.parse_args(argv)
    service_images = {}
    for item in args.service_image:
        name, _, image = item.partition('=')
        if not name or not image:
            p.error('--service-image requires SERVICE=IMAGE@sha256:...')
        if name in service_images:
            p.error('duplicate --service-image for service: ' + name)
        service_images[name] = image
    source = configure_catalog(args.catalog_url, args.catalog_sha256, args.catalog_revision)
    apps = catalog_apps()
    if args.action == 'catalog':
        if args.app != 'nginx':
            p.error('catalog action does not accept an application ID')
    elif args.action == 'install' and args.app not in apps:
        p.error('unknown managed application: ' + args.app)
    if args.action == 'tls':
        if args.disable_tls:
            if args.cert or args.key or args.no_redirect or args.tls_port != 443:
                p.error('--disable-tls cannot include certificate/port/redirect options')
        elif not (args.cert and args.key):
            p.error('TLS requires both --cert and --key, or --disable-tls')
    elif args.cert or args.key or args.disable_tls or args.no_redirect or args.tls_port != 443:
        p.error('TLS options apply only to tls action')
    if args.action == 'catalog':
        print('catalog source:', source)
        for app, spec in apps.items():
            if is_manifest(spec):
                flags = []
                if spec['revoked']:
                    flags.append('REVOKED')
                if spec['high_privilege']:
                    flags.append('HIGH PRIVILEGE')
                ports = ','.join('127.0.0.1:%s:%s/%s' % (p['published'], p['target'], p['protocol'])
                                 for _, p in manifest_ports(spec)) or 'host-network/no published ports'
                print('%s: %s; %s; services=%s; localhost=%s; %s' %
                      (app, spec['description'], ', '.join(flags) if flags else 'ordinary',
                       len(spec['services']), ports, spec['bytes'] // 1024 // 1024))
            else:
                spec = metadata(app)
                print('%s: %s; image=%s; localhost port %s; RAM limit %s / CPU 0.50 / PIDs 64; %s MiB minimum free disk (not a quota); Docker Compose v2/Python 3/Linux required' %
                      (app, spec['description'], spec['image'], spec['port'], spec['memory'], spec['bytes'] // 1024 // 1024))
        return
    if (args.auto_port or args.port is not None) and args.action not in ('install', 'reinstall'):
        p.error('Port options apply only to install/reinstall')
    if args.reuse_data and args.action != 'reinstall':
        p.error('--reuse-data applies only to reinstall')
    if args.risk_ack and args.action != 'install':
        p.error('--risk-ack applies only to install')
    if args.nas_path and args.action != 'install':
        p.error('--nas-path applies only to install')
    if service_images and args.action != 'update':
        p.error('--service-image applies only to update')
    if args.action == 'domain' and not args.confirm:
        p.error('Domain mapping requires explicit --confirm')
    if args.action != 'domain' and (args.domain or args.remove_domain):
        p.error('--domain/--remove-domain apply only to domain')
    if args.action == 'domain' and (args.domain is None) == (not args.remove_domain):
        p.error('Choose exactly one of --domain NAME or --remove-domain')
    operate(args.action, args.app, args.port, args.confirm, automatic=args.auto_port, reuse=args.reuse_data,
            domain=None if args.remove_domain else args.domain, listen=args.listen,
            tls={'cert': args.cert, 'key': args.key, 'listen': args.tls_port, 'redirect': not args.no_redirect}
            if args.action == 'tls' and not args.disable_tls else None,
            risk_ack=args.risk_ack, nas_path=args.nas_path, images=service_images)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Managed market failed:', error, file=sys.stderr)
        sys.exit(1)
