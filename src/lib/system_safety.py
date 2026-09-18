"""Small, checked transactions for legacy system menus. Never run on import."""
import argparse
import glob
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout


def regular(path):
    path = Path(path)
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError('Symlink path refused: ' + str(parent))
    st = path.stat()
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_nlink != 1:
        raise ValueError('Expected an owned, single-link regular file: ' + str(path))
    return st


def backup(path):
    regular(path)
    directory = Path(tempfile.mkdtemp(prefix='.fusionbox-backup-', dir=path.parent))
    saved = directory / path.name
    shutil.copy2(path, saved)
    os.chown(saved, path.stat().st_uid, path.stat().st_gid)
    print('Backup: ' + str(saved))
    return saved


def replace(path, content, metadata=None):
    fd, temporary = tempfile.mkstemp(prefix='.fusionbox-stage-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if metadata:
            shutil.copystat(metadata, temporary)
            st = metadata.stat()
            os.chown(temporary, st.st_uid, st.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def valid_keys(path):
    """Accept plain public keys only; options-bearing lines require manual review."""
    regular(path)
    if not shutil.which('ssh-keygen'):
        raise ValueError('ssh-keygen is required to validate public keys')
    keys = []
    with tempfile.TemporaryDirectory(prefix='fusionbox-key-') as directory:
        candidate = Path(directory) / 'key.pub'
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if not re.match(r'^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(?:256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\s+[A-Za-z0-9+/=]+(?:\s|$)', line):
                continue
            candidate.write_text(line + '\n')
            try:
                fingerprint = run('ssh-keygen', '-l', '-f', str(candidate)).strip()
            except subprocess.CalledProcessError:
                continue
            keys.append((number, fingerprint))
    return keys


def keys_add(path, line):
    if path.parent.is_symlink() or path.is_symlink():
        raise ValueError('Symlink key path refused')
    with tempfile.TemporaryDirectory(prefix='fusionbox-key-add-') as directory:
        candidate = Path(directory) / 'key.pub'
        candidate.write_text(line + '\n')
        if len(valid_keys(candidate)) != 1 or '\n' in line or '\r' in line:
            raise ValueError('Invalid plain public key')
    path.parent.mkdir(mode=0o700, exist_ok=True)
    if path.exists():
        saved = backup(path)
        content = path.read_text().rstrip('\n') + '\n' + line + '\n'
        replace(path, content, saved)
    else:
        replace(path, line + '\n')


def keys_action(path, action, number=None):
    keys = valid_keys(path)
    if action == 'list':
        for number, fingerprint in keys:
            print(f'{number}) {fingerprint}')
        print('Numbers are physical lines; comments, invalid and options-bearing keys are omitted.')
    elif action == 'check':
        if not keys:
            raise ValueError('No validated plain public key; test a separate key login first')
    elif action == 'delete':
        if number not in [item[0] for item in keys]:
            raise ValueError('Select a displayed physical line number')
        saved = backup(path)
        lines = path.read_text().splitlines(keepends=True)
        del lines[number - 1]
        replace(path, ''.join(lines), saved)


def no_match(path, seen=None):
    seen = set() if seen is None else seen
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    for line in path.read_text().splitlines():
        words = line.strip().split()
        if not words or words[0].startswith('#'):
            continue
        if words[0].lower() == 'match':
            raise ValueError('Match rules require manual SSH configuration review')
        if words[0].lower() == 'include':
            for pattern in words[1:]:
                if not os.path.isabs(pattern):
                    pattern = str(path.parent / pattern)
                for included in glob.glob(pattern):
                    no_match(Path(included), seen)


def ssh_change(path, directive, value):
    regular(path)
    if directive == 'Port':
        if not value.isascii() or not value.isdecimal() or not 1 <= int(value) <= 65535:
            raise ValueError('Invalid SSH port')
        value = str(int(value))
    elif directive != 'PasswordAuthentication' or value != 'no':
        raise ValueError('Unsupported SSH change')
    no_match(path)
    run('sshd', '-t', '-f', str(path))
    # Refuse service ambiguity (including socket activation) instead of restarting blindly.
    if any(subprocess.run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0
           for unit in ('ssh.socket', 'sshd.socket')):
        raise ValueError('SSH socket activation requires manual port/configuration handling')
    units = [unit for unit in ('sshd.service', 'ssh.service')
             if subprocess.run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0]
    if not units:
        raise ValueError('No active SSH service found')
    saved = backup(path)
    original = path.read_text()
    content = directive + ' ' + value + '\n' + ''.join(
        line for line in original.splitlines(keepends=True)
        if not re.match(r'^\s*' + directive + r'\s', line, re.I))
    attempted = False
    try:
        replace(path, content, saved)
        run('sshd', '-t', '-f', str(path))
        effective = run('sshd', '-T', '-f', str(path))
        values = [line.split()[1] for line in effective.splitlines()
                  if line.split() and line.split()[0] == directive.lower()]
        if values != [value]:
            raise ValueError('Includes or configuration override requested SSH setting')
        attempted = True
        run('systemctl', 'reload', units[0])
    except Exception:
        replace(path, original, saved)
        if attempted:
            try:
                run('sshd', '-t', '-f', str(path))
                run('systemctl', 'reload', units[0])
            except Exception:
                print('Rollback reload failed; runtime state unknown. Keep this session open.')
        raise
    print('SSH setting validated and reload accepted. Test a separate connection before closing this session.')
    if directive == 'PasswordAuthentication':
        print('Only PasswordAuthentication changed; keyboard-interactive/PAM and other authentication policies are unchanged.')


def swap_remove(path, fstab):
    st = regular(path)
    regular(fstab)
    if st.st_mode & 0o077:
        raise ValueError('Swap file must be private (0600 or stricter)')
    if path.name != 'swapfile':
        raise ValueError('Only the explicitly confirmed /swapfile is supported')
    # Explicit confirmation adopts this exact owned file; no wildcard/all-device cleanup.
    active = run('swapon', '--show=NAME', '--noheadings', '--raw').splitlines()
    for entry in active:
        if Path(entry).resolve() == path.resolve() and entry != str(path):
            raise ValueError('Active swap alias requires manual review')
    original = fstab.read_text()
    lines = original.splitlines(keepends=True)
    kept = []
    for line in lines:
        words = line.split()
        if words and not words[0].startswith('#') and words[0] == str(path):
            if len(words) < 3 or words[2] != 'swap':
                raise ValueError('Conflicting fstab entry')
        else:
            kept.append(line)
    saved = backup(fstab)
    if str(path) in active:
        run('swapoff', str(path))
    if any(Path(entry).resolve() == path.resolve() for entry in
           run('swapon', '--show=NAME', '--noheadings', '--raw').splitlines()):
        raise ValueError('Swap remains active; file and fstab preserved')
    if regular(path) != st:
        raise ValueError('Swap file identity or metadata changed; refusing removal')
    try:
        replace(fstab, ''.join(kept), saved)
        path.unlink()
    except Exception:
        replace(fstab, original, saved)
        print('Removal failed; fstab restored. Swap may be inactive; no automatic swapon attempted.')
        raise
    print('Removed only the confirmed swapfile; other swap entries preserved.')


def fail2ban_change(directory, retry, ban):
    for value in (retry, ban):
        if not re.fullmatch(r'[1-9][0-9]{0,8}', value):
            raise ValueError('Expected positive decimal integers (maximum 999999999)')
    target = directory / 'jail.d/99-fusionbox-sshd.local'
    marker = '# FusionBox managed sshd parameters v1\n'
    if target.is_symlink() or target.parent.is_symlink() or directory.is_symlink():
        raise ValueError('Symlink configuration refused')
    original = None
    saved = None
    if target.exists():
        regular(target)
        original = target.read_text()
        if not original.startswith(marker):
            raise ValueError('Unknown jail.d file; refusing overwrite')
        saved = backup(target)
    content = marker + f'[sshd]\nmaxretry = {retry}\nbantime = {ban}\nfindtime = 600\n'
    # Do not enable jails or guess SSH ports/backends; preserve administrator policy.
    with tempfile.TemporaryDirectory(prefix='fusionbox-f2b-') as temporary:
        staged = Path(temporary) / 'config'
        shutil.copytree(directory, staged)
        (staged / 'jail.d').mkdir(exist_ok=True)
        (staged / target.relative_to(directory)).write_text(content)
        run('fail2ban-client', '-c', str(staged), '-t')
    target.parent.mkdir(exist_ok=True)
    attempted = False
    try:
        replace(target, content, saved)
        run('fail2ban-client', '-c', str(directory), '-t')
        attempted = True
        run('fail2ban-client', 'reload')
    except Exception:
        if original is None:
            target.unlink(missing_ok=True)
        else:
            replace(target, original, saved)
        if attempted:
            try:
                run('fail2ban-client', 'reload')
            except Exception:
                print('Rollback reload failed; Fail2Ban runtime state unknown.')
        raise
    print('Owned sshd parameters saved and reload accepted; jail enablement/port/backend unchanged. Later overrides may take precedence.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['keys-add', 'keys-list', 'keys-check', 'keys-delete', 'ssh', 'swap', 'fail2ban'])
    parser.add_argument('values', nargs='*')
    args = parser.parse_args()
    try:
        if args.action == 'keys-add':
            keys_add(Path.home() / '.ssh/authorized_keys', sys.stdin.readline().rstrip('\n'))
        elif args.action.startswith('keys-'):
            keys_action(Path.home() / '.ssh/authorized_keys', args.action[5:],
                        int(args.values[0]) if args.values else None)
        elif args.action == 'ssh':
            ssh_change(Path('/etc/ssh/sshd_config'), *args.values)
        elif args.action == 'swap':
            swap_remove(Path('/swapfile'), Path('/etc/fstab'))
        else:
            fail2ban_change(Path('/etc/fail2ban'), *args.values)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Do not print command output; daemon diagnostics may contain secrets.
        print('Operation failed: ' + (str(error) if not isinstance(error, subprocess.SubprocessError) else 'command validation/activation failed'))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
