"""Strict, data-only v1 managed application catalog loading."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import urllib.parse
import urllib.request

from backup_jobs import atomic

SCHEMA_VERSION = 1
MAX_CATALOG_BYTES = 1024 * 1024
BUILTIN = Path(__file__).with_name('market-catalog.v1.json')
CACHE_NAME = '.market-catalog-cache-v1.json'
ID = re.compile(r'[a-z][a-z0-9-]{0,31}')
IMAGE = re.compile(r'[a-z0-9./:_-]+@sha256:[a-f0-9]{64}')
ENV = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
REVISION = re.compile(r'[A-Fa-f0-9]{7,64}')
ABS_PATH = re.compile(r'/[A-Za-z0-9_. /{}-]+')


def _exact(value, keys, required, where):
    if not isinstance(value, dict) or set(value) - set(keys) or set(required) - set(value):
        raise ValueError('Invalid catalog fields at ' + where)


def _path(value, where, template=False):
    candidate = value.replace('{nas_path}', '/nas') if isinstance(value, str) and template else value
    if not isinstance(value, str) or not isinstance(candidate, str) or not ABS_PATH.fullmatch(candidate) or '..' in PurePosixPath(candidate).parts:
        raise ValueError('Invalid absolute path at ' + where)
    marker = value.count('{nas_path}')
    if marker and (not template or marker != 1 or not value.startswith('{nas_path}/')):
        raise ValueError('Invalid NAS path template at ' + where)
    return value


def _port(value, where):
    _exact(value, ('published', 'target', 'protocol'), ('published', 'target', 'protocol'), where)
    if (type(value['published']) is not int or not 1024 <= value['published'] <= 65535 or
            type(value['target']) is not int or not 1 <= value['target'] <= 65535 or
            value['protocol'] not in ('tcp', 'udp')):
        raise ValueError('Invalid port at ' + where)
    return dict(value)


def _volume(value, where):
    _exact(value, ('name', 'target', 'read_only'), ('name', 'target', 'read_only'), where)
    if not ID.fullmatch(value.get('name', '')) or type(value.get('read_only')) is not bool:
        raise ValueError('Invalid named volume at ' + where)
    _path(value.get('target'), where)
    return dict(value)


def _bind(value, where):
    _exact(value, ('source', 'target', 'read_only'), ('source', 'target', 'read_only'), where)
    _path(value.get('source'), where, True)
    _path(value.get('target'), where)
    if type(value.get('read_only')) is not bool:
        raise ValueError('Invalid bind mount at ' + where)
    return dict(value)


def _device(value, where):
    _exact(value, ('source', 'target', 'permissions'), ('source', 'target', 'permissions'), where)
    _path(value.get('source'), where)
    _path(value.get('target'), where)
    permissions = value.get('permissions')
    if not isinstance(permissions, str) or any(permissions.count(x) > 1 for x in permissions) or not re.fullmatch(r'[rwm]{1,3}', permissions):
        raise ValueError('Invalid device permissions at ' + where)
    return dict(value)


def _service(value, where):
    keys = ('id', 'image', 'command', 'environment', 'user', 'ports', 'volumes', 'binds',
            'devices', 'network_mode', 'docker_socket', 'memory', 'cpus', 'pids_limit',
            'health', 'health_retries')
    required = ('id', 'image', 'ports', 'volumes', 'binds', 'devices', 'network_mode',
                'docker_socket', 'memory', 'cpus', 'pids_limit', 'health', 'health_retries')
    _exact(value, keys, required, where)
    if not ID.fullmatch(value.get('id', '')) or not IMAGE.fullmatch(value.get('image', '')):
        raise ValueError('Invalid service identity/image at ' + where)
    if value['network_mode'] not in ('bridge', 'host') or type(value['docker_socket']) is not bool:
        raise ValueError('Invalid service network/socket setting at ' + where)
    if (not isinstance(value['memory'], str) or not re.fullmatch(r'[1-9][0-9]*m', value['memory']) or
            not isinstance(value['cpus'], str) or not re.fullmatch(r'(?:0\.[1-9][0-9]?|[1-9][0-9]*(?:\.[0-9]{1,2})?)', value['cpus']) or
            type(value['pids_limit']) is not int or not 16 <= value['pids_limit'] <= 4096 or
            type(value['health_retries']) is not int or not 1 <= value['health_retries'] <= 300):
        raise ValueError('Invalid service resource limits at ' + where)
    for field in ('ports', 'volumes', 'binds', 'devices', 'health'):
        if not isinstance(value[field], list):
            raise ValueError('Invalid list at ' + where + '.' + field)
    if not value['health'] or any(not isinstance(x, str) or not x or '\x00' in x for x in value['health']):
        raise ValueError('Invalid healthcheck at ' + where)
    result = dict(value)
    result['ports'] = [_port(x, where + '.ports') for x in value['ports']]
    result['volumes'] = [_volume(x, where + '.volumes') for x in value['volumes']]
    result['binds'] = [_bind(x, where + '.binds') for x in value['binds']]
    result['devices'] = [_device(x, where + '.devices') for x in value['devices']]
    if value['network_mode'] == 'host' and value['ports']:
        raise ValueError('Host-network services cannot declare published ports')
    if 'command' in value and (not isinstance(value['command'], list) or not value['command'] or
                               any(not isinstance(x, str) or '\x00' in x for x in value['command'])):
        raise ValueError('Invalid command at ' + where)
    if 'environment' in value and (not isinstance(value['environment'], dict) or
            any(not isinstance(k, str) or not ENV.fullmatch(k) or not isinstance(v, str) or '\x00' in v
                for k, v in value['environment'].items())):
        raise ValueError('Invalid environment at ' + where)
    if 'user' in value and (not isinstance(value['user'], str) or not re.fullmatch(r'[0-9]+(?::[0-9]+)?', value['user'])):
        raise ValueError('Invalid service user at ' + where)
    return result


def parse(raw):
    """Parse JSON bytes/text and return a fully validated catalog dictionary."""
    if isinstance(raw, bytes):
        if len(raw) > MAX_CATALOG_BYTES:
            raise ValueError('Catalog exceeds 1 MiB limit')
        try:
            raw = raw.decode('utf-8')
        except UnicodeDecodeError as error:
            raise ValueError('Catalog must be UTF-8 JSON') from error
    if not isinstance(raw, str) or len(raw.encode('utf-8')) > MAX_CATALOG_BYTES:
        raise ValueError('Catalog exceeds 1 MiB limit')
    try:
        value = json.loads(raw)
    except (json.JSONDecodeError, TypeError) as error:
        raise ValueError('Invalid catalog JSON') from error
    _exact(value, ('schema_version', 'catalog_id', 'revision', 'apps'),
           ('schema_version', 'catalog_id', 'revision', 'apps'), 'catalog')
    if value['schema_version'] != SCHEMA_VERSION or not ID.fullmatch(value.get('catalog_id', '')):
        raise ValueError('Unsupported catalog schema or identity')
    if not isinstance(value['revision'], str) or not value['revision'] or len(value['revision']) > 64:
        raise ValueError('Invalid catalog revision')
    if not isinstance(value['apps'], list) or not value['apps']:
        raise ValueError('Catalog apps must be a non-empty list')
    apps = {}
    for index, app in enumerate(value['apps']):
        where = 'apps[%s]' % index
        _exact(app, ('id', 'name', 'description', 'revoked', 'high_privilege', 'risk_acknowledgement',
                     'domain', 'bytes', 'nas_path', 'services'),
               ('id', 'name', 'description', 'revoked', 'high_privilege', 'domain', 'bytes',
                'nas_path', 'services'), where)
        if (not ID.fullmatch(app.get('id', '')) or app['id'] in apps or
                not isinstance(app['name'], str) or not app['name'] or len(app['name']) > 80 or
                not isinstance(app['description'], str) or not app['description'] or len(app['description']) > 500 or
                type(app['revoked']) is not bool or type(app['high_privilege']) is not bool or
                type(app['domain']) is not bool or type(app['nas_path']) is not bool or
                type(app['bytes']) is not int or app['bytes'] <= 0 or
                not isinstance(app['services'], list) or not app['services']):
            raise ValueError('Invalid application at ' + where)
        services = [_service(x, where + '.services') for x in app['services']]
        if len({x['id'] for x in services}) != len(services):
            raise ValueError('Duplicate service ID at ' + where)
        published_ports = [(port['published'], port['protocol']) for service in services for port in service['ports']]
        if len(set(published_ports)) != len(published_ports):
            raise ValueError('Duplicate published port/protocol at ' + where)
        inferred = any(s['docker_socket'] or s['devices'] or s['network_mode'] == 'host' or s['binds'] for s in services)
        if inferred != app['high_privilege']:
            raise ValueError('high_privilege must exactly match declared capabilities at ' + where)
        ack = app.get('risk_acknowledgement')
        if app['high_privilege']:
            if not isinstance(ack, str) or ack != 'I ACCEPT HIGH PRIVILEGE: ' + app['id']:
                raise ValueError('High-privilege application requires exact risk acknowledgement')
            if app['domain']:
                raise ValueError('High-privilege application cannot enable managed domain mapping')
        elif ack is not None:
            raise ValueError('Ordinary application cannot declare risk acknowledgement')
        uses_nas = any('{nas_path}' in b['source'] for s in services for b in s['binds'])
        has_fixed_bind = any('{nas_path}' not in b['source'] for s in services for b in s['binds'])
        if has_fixed_bind:
            raise ValueError('Host bind mounts must use the explicit {nas_path} template at ' + where)
        if uses_nas != app['nas_path']:
            raise ValueError('nas_path must exactly match bind templates at ' + where)
        apps[app['id']] = dict(app, services=services)
    return {'schema_version': SCHEMA_VERSION, 'catalog_id': value['catalog_id'],
            'revision': value['revision'], 'apps': apps}


def app_digest(app):
    value = json.dumps(app, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    return hashlib.sha256(value.encode()).hexdigest()


def _read_remote(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('Remote catalog URL must be HTTPS without credentials or fragment')
    request = urllib.request.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'FusionBox-market/1'})
    with urllib.request.urlopen(request, timeout=10) as response:
        if urllib.parse.urlsplit(response.geturl()).scheme != 'https':
            raise ValueError('Remote catalog redirected outside HTTPS')
        length = response.headers.get('Content-Length')
        if length and int(length) > MAX_CATALOG_BYTES:
            raise ValueError('Catalog exceeds 1 MiB limit')
        body = response.read(MAX_CATALOG_BYTES + 1)
    if len(body) > MAX_CATALOG_BYTES:
        raise ValueError('Catalog exceeds 1 MiB limit')
    return body


def _pins(sha256, revision):
    if sha256 is not None and (not isinstance(sha256, str) or not re.fullmatch(r'[a-f0-9]{64}', sha256)):
        raise ValueError('Catalog SHA256 must be 64 lowercase hex characters')
    if revision is not None and (not isinstance(revision, str) or not REVISION.fullmatch(revision)):
        raise ValueError('Catalog revision pin must be a 7-64 character commit identifier')
    if sha256 is None and revision is None:
        raise ValueError('Remote catalog requires --catalog-sha256 and/or --catalog-revision')


def load(cache_dir, url=None, sha256=None, revision=None, opener=None):
    """Load remote, matching atomic cache, or the built-in catalog in that order."""
    builtin = parse(BUILTIN.read_bytes())
    if url is None:
        if sha256 is not None or revision is not None:
            raise ValueError('Catalog pins require --catalog-url')
        return builtin, 'builtin'
    _pins(sha256, revision)
    parsed_url = urllib.parse.urlsplit(url)
    if parsed_url.scheme != 'https' or not parsed_url.netloc or parsed_url.username or parsed_url.password or parsed_url.fragment:
        raise ValueError('Remote catalog URL must be HTTPS without credentials or fragment')
    cache = Path(cache_dir) / CACHE_NAME
    try:
        body = opener(url) if opener else _read_remote(url)
        digest = hashlib.sha256(body).hexdigest()
        catalog = parse(body)
        if sha256 is not None and digest != sha256:
            raise ValueError('Remote catalog SHA256 mismatch')
        if revision is not None and catalog['revision'] != revision:
            raise ValueError('Remote catalog revision mismatch')
        envelope = {'owner': 'fusionbox-market-catalog-cache-v1', 'url': url, 'sha256': sha256,
                    'revision': revision, 'body_sha256': digest, 'body': body.decode('utf-8')}
        atomic(cache, json.dumps(envelope, sort_keys=True) + '\n')
        return catalog, 'remote'
    except Exception as remote_error:
        try:
            if cache.is_symlink():
                raise ValueError('Catalog cache cannot be a symlink')
            envelope = json.loads(cache.read_text())
            if (set(envelope) != {'owner', 'url', 'sha256', 'revision', 'body_sha256', 'body'} or
                    envelope['owner'] != 'fusionbox-market-catalog-cache-v1' or envelope['url'] != url or
                    envelope['sha256'] != sha256 or envelope['revision'] != revision or
                    hashlib.sha256(envelope['body'].encode()).hexdigest() != envelope['body_sha256']):
                raise ValueError('Catalog cache identity mismatch')
            catalog = parse(envelope['body'])
            if sha256 is not None and envelope['body_sha256'] != sha256:
                raise ValueError('Cached catalog SHA256 mismatch')
            if revision is not None and catalog['revision'] != revision:
                raise ValueError('Cached catalog revision mismatch')
            return catalog, 'cache'
        except Exception:
            return builtin, 'builtin-fallback: ' + str(remote_error)
