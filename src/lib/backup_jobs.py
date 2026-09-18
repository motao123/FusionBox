"""Owned daily configuration snapshots only; never stop services or edit user cron."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import archive

OWNER = 'fusionbox-config-backup-v1'


def atomic(path, value, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.stage-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(value)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def paths(root, job):
    if not re.fullmatch('[a-z][a-z0-9-]{0,31}', job):
        raise ValueError('Job ID must be 1-32 lowercase letters/digits/hyphens, starting with a letter')
    base = root / 'etc/fusionbox/backup-jobs'
    cron = root / ('etc/cron.d/fusionbox-backup-' + job)
    state = root / ('var/lib/fusionbox/backup-jobs/' + job)
    for target in (base, cron, state):
        if any(p.is_symlink() for p in (target, *target.parents)):
            raise ValueError('Refusing symlink-managed job paths')
    return base / (job + '.json'), cron, state


def load(path):
    if path.is_symlink():
        raise ValueError('Refusing symlink job')
    data = json.loads(path.read_text())
    if data.get('owner') != OWNER or data.get('scope') != 'config':
        raise ValueError('Unknown job ownership or scope')
    return data


def create(root, job, hour, minute, accepted):
    if not accepted:
        raise ValueError('Explicit stable-config acknowledgement required')
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        raise ValueError('Invalid daily time')
    conf, cron, state = paths(root, job)
    if conf.exists() or cron.exists() or conf.is_symlink() or cron.is_symlink():
        raise ValueError('Job or cron path occupied; remove owned job first')
    helper = str(Path(__file__).resolve())
    python = str(Path(sys.executable).resolve())
    # Cron shell arguments cannot contain percent/newlines; avoid shell quoting ambiguity.
    if not all(re.fullmatch(r'/[A-Za-z0-9_./-]+', p) for p in (helper, python)):
        raise ValueError('Installed helper/Python path is not cron-safe')
    data = {'owner': OWNER, 'scope': 'config', 'job': job, 'hour': hour, 'minute': minute,
            'precondition': 'No configuration writers during snapshot; no database or website data'}
    atomic(conf, json.dumps(data) + '\n')
    try:
        atomic(cron, f'# {OWNER}\nSHELL=/bin/sh\nPATH=/usr/local/bin:/usr/bin:/bin\n{minute} {hour} * * * root {python} {helper} run {job}\n', 0o600)
    except BaseException:
        conf.unlink()
        raise


def run(root, job):
    import fcntl
    conf, cron, state = paths(root, job)
    load(conf)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(state, 0o700)
    with (state / 'run.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Job already running')
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        target = state / ('config-' + stamp + '.tar.gz')
        try:
            archive.create(target, 'config', root)
        except BaseException:
            atomic(state / 'status.json', json.dumps({'success': False, 'time': stamp, 'reason': 'snapshot failed; inspect source paths/permissions'}) + '\n')
            raise
        atomic(state / 'status.json', json.dumps({'success': True, 'time': stamp, 'archive': target.name}) + '\n')
        print(target)


def remove(root, job):
    conf, cron, state = paths(root, job)
    load(conf)
    if cron.is_symlink() or (cron.exists() and cron.read_text().splitlines()[0] != '# ' + OWNER):
        raise ValueError('Unknown cron ownership; preserved')
    cron.unlink(missing_ok=True)
    conf.unlink()
    print('Schedule removed; archives, status and running snapshots retained:', state)


def listing(root):
    for conf in sorted((root / 'etc/fusionbox/backup-jobs').glob('*.json')):
        data = load(conf)
        _, cron, state = paths(root, data['job'])
        print(data['job'], f"{data['hour']:02}:{data['minute']:02}", 'config only', 'scheduled' if cron.exists() else 'missing cron')
        status = state / 'status.json'
        if status.is_file():
            print(status.read_text().strip())


def legacy(root):
    candidates = [root / 'etc/crontab', *(root / 'etc/cron.d').glob('*')]
    if root == Path('/'):
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
        sources = [('root crontab', result.stdout)]
    else:
        sources = []
    for path in candidates:
        if path.is_file() and not path.is_symlink():
            sources.append((str(path), path.read_text(errors='replace')))
    for source, text in sources:
        for number, line in enumerate(text.splitlines(), 1):
            if not line.lstrip().startswith('#') and re.search(r'site_backup_|rclone|rsync|\bscp\b|\btar\s', line):
                # Do not print command text: legacy commands may contain credentials.
                print(f'{source}:{number}: possible legacy backup; manual review required; unchanged')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description='Daily local nginx/caddy configuration snapshots. No remote transfer, data backup or service stops. Config writers must be idle; links/special files are refused.')
    parser.add_argument('action', choices=('create', 'list', 'remove', 'run', 'legacy'))
    parser.add_argument('job', nargs='?')
    parser.add_argument('--hour', type=int, default=3)
    parser.add_argument('--minute', type=int, default=0)
    parser.add_argument('--ack-stable-config', action='store_true')
    args = parser.parse_args()
    root = Path('/')
    if args.action in ('list', 'legacy'):
        globals()[{'list': 'listing', 'legacy': 'legacy'}[args.action]](root)
    elif args.action == 'create':
        create(root, args.job or '', args.hour, args.minute, args.ack_stable_config)
    else:
        globals()[args.action](root, args.job or '')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Backup job failed:', error, file=sys.stderr)
        sys.exit(1)
