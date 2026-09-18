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

import compose_backup as cb
from backup_jobs import atomic

OWNER = 'fusionbox-market-v1'
CATALOG = {'nginx': {'image': 'nginx:stable-alpine', 'port': 8080, 'bytes': 256 * 1024 * 1024}}


def document(record, image=None):
    m = record['market']
    labels = {'io.fusionbox.market': m['token']}
    return {'services': {'app': {
        'image': image or m['image'], 'container_name': record['project'] + '-app',
        'network_mode': 'bridge', 'restart': 'unless-stopped',
        'ports': ['127.0.0.1:%s:80' % m['port']],
        'volumes': ['data:/usr/share/nginx/html:ro'], 'labels': labels,
        'mem_limit': '64m', 'cpus': '0.50', 'pids_limit': 64,
        'logging': {'driver': 'json-file', 'options': {'max-size': '5m', 'max-file': '2'}},
        'healthcheck': {'test': ['CMD', 'wget', '-q', '-O', '/dev/null', 'http://127.0.0.1/'],
                        'interval': '2s', 'timeout': '2s', 'retries': 10}}},
        'volumes': {'data': {'name': record['project'] + '_data', 'labels': labels}}}


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
        for mount in c.get('Mounts', []):
            if (mount['Type'] != 'volume' or mount.get('Name') != project + '_data' or
                    mount.get('Destination') != '/usr/share/nginx/html' or mount.get('RW')):
                raise ValueError('Unexpected application storage')
    volumes = cb.docker('volume', 'ls', '-q').decode().split()
    if project + '_data' in volumes:
        v = cb.js('volume', 'inspect', project + '_data')[0]
        labels = v.get('Labels') or {}
        if (labels.get('io.fusionbox.market') != token or
                labels.get('com.docker.compose.project') != project or
                v['Driver'] != 'local' or v.get('Options')):
            raise ValueError('Unknown data volume ownership')
        users = cb.docker('ps', '-aq', '--filter', 'volume=' + project + '_data').decode().split()
        if set(users) - set(ids):
            raise ValueError('Data volume shared outside managed app')
    elif containers:
        raise ValueError('Managed data volume missing')
    return containers


def preflight(port, check_port=True):
    if type(port) is not int or not 1024 <= port <= 65535:
        raise ValueError('Port must be 1024-65535')
    cb.docker('compose', 'version')
    root = Path(cb.js('info', '--format', '{{json .DockerRootDir}}'))
    for path in (cb.BASE, root):
        if shutil.disk_usage(path).free < CATALOG['nginx']['bytes']:
            raise ValueError('Insufficient disk space (256 MiB required on registry and Docker storage)')
    if check_port:
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', port))
        # Docker may publish without a userspace listening socket.
        ids = cb.docker('ps', '-q').decode().split()
        for c in cb.js('inspect', *ids) if ids else []:
            for bindings in (c['NetworkSettings'].get('Ports') or {}).values():
                if any(int(b['HostPort']) == port for b in bindings or []):
                    raise ValueError('Port already published by Docker')


def select_port(preferred=8080, automatic=False):
    if not automatic:
        preflight(preferred)
        return preferred
    if not 1024 <= preferred <= 65535:
        raise ValueError('Port must be 1024-65535')
    for port in range(preferred, min(preferred + 20, 65536)):
        try:
            preflight(port)
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
    record['market']['port'] = select_port(record['market']['port'] if port is None else port, automatic)
    try:
        write_compose(record)
        up(record)
        record['market']['state'] = 'healthy'
        save(registry, record)
    except BaseException:
        # The preflight proved this namespace empty. Revalidate labels before cleanup.
        # No volume is removed, and the app has read-only access to retained content.
        try:
            for container in resources(record):
                cb.docker('stop', container['Id'])
                cb.docker('rm', container['Id'])
        except BaseException:
            raise RuntimeError('Reinstall failed and container cleanup failed; original registry/config/data retained; inspect owned resources before retry') from None
        finally:
            write_compose(original)
        raise RuntimeError('Reinstall failed; newly created containers removed; original registry/config/data retained') from None
    print('Reinstall completed; healthy; localhost port ' + str(record['market']['port']))


def pull():
    image = CATALOG['nginx']['image']
    cb.docker('pull', image)
    return cb.js('image', 'inspect', image)[0]['Id']


def up(record):
    cb.docker('compose', '-p', record['project'], '-f', record['compose'],
              'up', '-d', '--wait', '--wait-timeout', '45', '--pull', 'never')
    if health(record) != 'healthy':
        raise RuntimeError('Application health check failed')


def health(record):
    containers = resources(record)
    if not containers:
        return 'absent; data/config retained'
    state = containers[0]['State']
    if not state['Running']:
        return 'stopped'
    return state.get('Health', {}).get('Status', 'unknown')


def operate(action, app='nginx', port=None, accepted=False, project=None, automatic=False, reuse=False):
    if app not in CATALOG:
        raise ValueError('Unsupported managed application')
    project = project or 'fb-market-' + app
    if action != 'status' and not accepted:
        raise ValueError('Explicit --confirm required (update/uninstall cause downtime; data retained)')
    with cb.lock(project) as registry:
        if action == 'install':
            compose = cb.BASE / (project + '.compose.json')
            if registry.exists() or registry.is_symlink() or compose.exists() or compose.is_symlink():
                raise ValueError('Existing registry/configuration; refusing adoption')
            port = select_port(8080 if port is None else port, automatic)
            if (cb.docker('ps', '-aq', '--filter', 'name=^/' + project + '-app$').strip() or
                    cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip() or
                    project + '_data' in cb.docker('volume', 'ls', '-q').decode().split()):
                raise ValueError('Existing unmanaged Docker resources; refusing adoption')
            record = {'owner': cb.OWNER, 'project': project, 'compose': str(compose.absolute()),
                      'market': {'owner': OWNER, 'app': app, 'token': uuid.uuid4().hex,
                                 'port': port, 'image': pull(), 'state': 'installing'}}
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
            if action == 'reinstall':
                if not reuse:
                    raise ValueError('Explicit --reuse-data required for retained content')
                reinstall(registry, record, port, automatic)
                return
            containers = resources(record)
            if action == 'status':
                print('managed-compose', app, record['market']['state'], health(record),
                      'http://127.0.0.1:' + str(record['market']['port']))
                if record['market']['state'] == 'uninstalled':
                    print('Retained data: reinstall nginx --confirm --reuse-data [--auto-port]')
                return
            if action == 'uninstall':
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
            preflight(record['market']['port'], False)
            candidate = pull()
            if candidate == record['market']['image']:
                print('Already using current catalog image')
                return
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
    p.add_argument('action', choices=('catalog', 'install', 'reinstall', 'status', 'update', 'uninstall'))
    p.add_argument('app', nargs='?', default='nginx', choices=tuple(CATALOG))
    p.add_argument('--port', type=int, help='Preferred port; default 8080 or retained port for reinstall')
    p.add_argument('--auto-port', action='store_true', help='Probe at most 20 localhost ports; not a reservation')
    p.add_argument('--reuse-data', action='store_true', help='Explicitly reuse owned retained data on reinstall')
    p.add_argument('--confirm', action='store_true')
    args = p.parse_args()
    if args.action == 'catalog':
        print('nginx: static web server; managed Compose; localhost only; persistent read-only content; 256 MiB free disk; Docker Compose v2/Python 3/Linux required')
        return
    if (args.auto_port or args.port is not None) and args.action not in ('install', 'reinstall'):
        p.error('Port options apply only to install/reinstall')
    if args.reuse_data and args.action != 'reinstall':
        p.error('--reuse-data applies only to reinstall')
    operate(args.action, args.app, args.port, args.confirm, automatic=args.auto_port, reuse=args.reuse_data)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Managed market failed:', error, file=sys.stderr)
        sys.exit(1)
