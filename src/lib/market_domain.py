"""Owned HTTP-only host Nginx mappings for managed apps; no ACME or firewall changes."""
import copy
import re
import subprocess
from pathlib import Path

import compose_backup as cb
from backup_jobs import atomic

CONF = Path('/etc/nginx/conf.d')


def nginx(*args):
    result = subprocess.run(['nginx', *args], capture_output=True)
    if result.returncode:
        raise RuntimeError('Nginx validation/reload failed')
    return result.stdout.decode() + result.stderr.decode()


def validate(domain):
    if (not isinstance(domain, str) or len(domain) > 253 or domain != domain.lower() or
            len(domain.split('.')) < 2 or not re.search('[a-z]', domain.split('.')[-1]) or
            any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
                for label in domain.split('.'))):
        raise ValueError('Domain must be a lowercase ASCII DNS name (no wildcard, IP, URL or path)')
    return domain


def path(record):
    project = record['project']
    if not re.fullmatch('[a-z0-9][a-z0-9_-]{0,47}', project):
        raise ValueError('Invalid project identity')
    target = CONF / ('fusionbox-market-' + project + '.conf')
    if not target.is_absolute() or not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(target)) or '..' in target.parts:
        raise ValueError('Unsafe Nginx configuration path')
    cb.no_links(target)
    return target


def render(record):
    mapping = record['market']['domain']
    if (set(mapping) != {'name', 'listen', 'mode', 'enabled'} or mapping['mode'] != 'http-only' or
            type(mapping['enabled']) is not bool):
        raise ValueError('Unknown domain mapping type; TLS unavailable')
    domain = validate(mapping['name'])
    port = record['market']['port']
    listen = mapping['listen']
    if type(port) is not int or not 1024 <= port <= 65535:
        raise ValueError('Invalid managed upstream port')
    if type(listen) is not int or not 1 <= listen <= 65535 or listen == port:
        raise ValueError('Invalid HTTP listen port (must differ from upstream)')
    token = record['market']['token']
    if not re.fullmatch('[a-f0-9]{32}', token):
        raise ValueError('Invalid ownership token')
    backend = (f'proxy_pass http://127.0.0.1:{port};' if mapping['enabled'] else 'return 503;')
    return f'''# FusionBox managed HTTP mapping {token}
server {{
    listen {listen};
    server_name {domain};
    # Reject unmatched Host even when this is the first server on the port.
    if ($host != {domain}) {{ return 404; }}
    location / {{
        {backend}
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
}}
'''


def owned(record):
    target = path(record)
    if 'domain' in record['market']:
        if not target.is_file() or target.read_text() != render(record):
            raise ValueError('Owned domain configuration missing or changed; manual recovery required')
    elif target.exists():
        raise ValueError('Unowned domain configuration exists; refusing overwrite')
    return target


def collision(dump, target, domain):
    # nginx -T emits resolved includes, including sites-enabled links. Remove only
    # our exact owned file. Reject regex names conservatively rather than guessing.
    current = None
    other = []
    for line in dump.splitlines():
        if line.startswith('# configuration file ') and line.endswith(':'):
            current = line[len('# configuration file '):-1]
        elif current != str(target):
            other.append(line)
    text = re.sub(r'#[^\n]*', '', '\n'.join(other))
    for names in re.findall(r'\bserver_name\s+([^;]+);', text):
        for name in names.split():
            name = name.strip('\"\'').lower()
            if (name.startswith('~') or '$' in name or name == domain or
                    name == '*' or name == '.' + domain or
                    (name.startswith('*.') and domain.endswith(name[1:])) or
                    (name.startswith('.') and domain.endswith(name)) or
                    (name.endswith('.*') and domain.startswith(name[:-1]))):
                raise ValueError('Domain collides with another Nginx server_name (regex names require manual review)')
    # Require the conventional conf.d glob; do not edit the host main config.
    if not re.search(r'\binclude\s+' + re.escape(str(CONF)) + r'/\*\.conf\s*;', text):
        raise ValueError('Host Nginx must already include the conf.d/*.conf directory')


def change(registry, record, domain=None, listen=80, enabled=True):
    """Caller holds global Compose registry lock. External Nginx writers must be stopped."""
    target = owned(record)
    candidate = copy.deepcopy(record)
    if domain is None:
        if 'domain' not in candidate['market']:
            raise ValueError('No owned domain mapping to remove')
        del candidate['market']['domain']
        text = None
    else:
        candidate['market']['domain'] = {'name': validate(domain), 'listen': listen, 'mode': 'http-only', 'enabled': enabled}
        text = render(candidate)
    dump = nginx('-T')
    if domain is not None:
        collision(dump, target, domain)
    # Retain recovery metadata before touching active config. Never overwrite a
    # pending recovery journal; interruption requires operator review.
    journal = cb.BASE / (record['project'] + '.domain-recovery.json')
    stage = cb.BASE / (record['project'] + '.domain-stage.conf')
    cb.no_links(stage)
    cb.no_links(Path(str(stage) + '.pid'))
    if any(c in str(stage) for c in ('\n', '\r', '"', '$', ';')):
        raise ValueError('Unsafe staging configuration path')
    cb.no_links(journal)
    if journal.exists():
        raise ValueError('Pending domain recovery journal; manual recovery required')
    import json
    atomic(journal, json.dumps({'before': record, 'after': candidate}) + '\n')
    before = target.read_text() if target.exists() else None
    try:
        if text is not None:
            # Standalone parse test BEFORE making the candidate an active include.
            atomic(stage, 'pid "' + str(stage) + '.pid";\nerror_log stderr;\nevents {}\nhttp {\n' + text + '}\n')
            nginx('-t', '-c', str(stage))
        owned(record)
        if text is None:
            target.unlink()
        else:
            atomic(target, text)
        nginx('-t')
        nginx('-s', 'reload')
        atomic(registry, json.dumps(candidate) + '\n')
    except BaseException:
        try:
            # Refuse to clobber an external writer even during recovery.
            actual = target.read_text() if target.exists() else None
            if actual not in (before, text):
                raise ValueError('Configuration changed during transaction')
            cb.no_links(target)
            if before is None:
                if target.exists():
                    target.unlink()
            else:
                atomic(target, before)
            nginx('-t')
            nginx('-s', 'reload')
            atomic(registry, json.dumps(record) + '\n')
        except BaseException:
            raise RuntimeError('Domain change AND rollback failed; recovery journal retained; runtime state unknown; manual recovery required') from None
        journal.unlink()
        raise RuntimeError('Domain change failed; previous configuration restored and reloaded') from None
    else:
        journal.unlink()
    finally:
        if stage.exists():
            stage.unlink()
        stage_pid = Path(str(stage) + '.pid')
        if stage_pid.exists():
            stage_pid.unlink()
    print('HTTP-only domain mapping applied; TLS unavailable; DNS/reachability not verified' if domain else
          'Domain mapping removed; app remains localhost-only')


def status(record):
    owned(record)
    mapping = record['market'].get('domain')
    if mapping:
        print('HTTP-only domain: http://' + mapping['name'] + ':' + str(mapping['listen']),
              '(configured; DNS/public reachability unverified; TLS unavailable)',
              'enabled' if mapping['enabled'] else 'suspended: returns 503')
    else:
        print('Access: localhost-direct; no public direct port or domain mapping')
    print('Localhost upstream remains accessible locally; no firewall isolation is claimed')
    if (cb.BASE / (record['project'] + '.domain-recovery.json')).exists():
        print('WARNING: pending domain recovery journal; runtime state unknown; manual recovery required')
