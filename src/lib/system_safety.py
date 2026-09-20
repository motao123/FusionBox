"""Small, checked transactions for legacy system menus. Never run on import."""
import argparse
import base64
import glob
import hashlib
import json
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


def _command_output(*args):
    try:
        result = subprocess.run(args, check=False, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None, None
    return result.returncode, result.stdout


def ssh_preflight(path=Path('/etc/ssh/sshd_config')):
    """Read-only SSH upgrade/switch preflight; never reloads or edits sshd."""
    path = Path(path)
    regular(path)
    if not shutil.which('sshd'):
        raise ValueError('sshd is required for SSH preflight')
    config_test = _command_output('sshd', '-t', '-f', str(path))
    if config_test[0] != 0:
        raise ValueError('sshd configuration validation failed')
    effective_code, effective_text = _command_output('sshd', '-T', '-f', str(path))
    if effective_code != 0 or effective_text is None:
        raise ValueError('Unable to read effective sshd configuration')
    values = {}
    for line in effective_text.splitlines():
        words = line.split(None, 1)
        if len(words) == 2 and words[0] in {
                'port', 'listenaddress', 'permitrootlogin', 'passwordauthentication',
                'kbdinteractiveauthentication', 'pubkeyauthentication', 'authorizedkeysfile'}:
            values.setdefault(words[0], []).append(words[1])
    units = {}
    for unit in ('ssh.service', 'sshd.service', 'ssh.socket', 'sshd.socket'):
        code, output = _command_output('systemctl', 'is-active', unit)
        state = (output or '').strip()
        units[unit] = True if code == 0 and state == 'active' else (
            False if code in (3, 4) and state in ('inactive', 'failed', 'unknown') else None)
    listeners = None
    if shutil.which('ss'):
        code, output = _command_output('ss', '-H', '-ltn')
        if code == 0 and output is not None:
            listeners = []
            for line in output.splitlines():
                words = line.split()
                if len(words) >= 4:
                    listeners.append(words[3])
    result = {
        'config': str(path),
        'config_valid': True,
        'effective': values,
        'service': units,
        'listeners': listeners,
        'current_session': bool(os.environ.get('SSH_CONNECTION')),
        'mutation_performed': False,
        'switch_allowed': False,
        'switch_blockers': ['candidate build, independent login and rollback are not verified'],
        'socket_activation_detected': any(
            units.get(unit) is True for unit in ('ssh.socket', 'sshd.socket')),
        'service_state_complete': all(value is not None for value in units.values()),
    }
    print(json.dumps(result, sort_keys=True))
    return result


def ssh_change(path, directive, value):
    regular(path)
    if directive == 'Port':
        if not value.isascii() or not value.isdecimal() or not 1 <= int(value) <= 65535:
            raise ValueError('Invalid SSH port')
        value = str(int(value))
    elif directive == 'PermitRootLogin':
        if value not in ('yes', 'prohibit-password', 'no'):
            raise ValueError('PermitRootLogin must be yes, prohibit-password or no')
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
        if directive == 'PermitRootLogin' and value == 'prohibit-password':
            # sshd reports the alias "without-password" in -T output.
            values = ['prohibit-password' if v == 'without-password' else v for v in values]
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


NAME_RE = re.compile(r'^[a-z_][a-z0-9_-]{0,31}$')
SUDO_MARKER = '# FusionBox managed sudo grant v1\n'
SUDO_PREFIX = '90-fusionbox-'


def _validate_name(name):
    if not NAME_RE.fullmatch(name or ''):
        raise ValueError('Invalid username (lowercase first letter, digits/_/- allowed, max 32 chars)')
    return name


def _lookup(name):
    import pwd
    try:
        return pwd.getpwnam(name)
    except KeyError:
        raise ValueError('No such user: ' + name)


def user_add(name, shell='/bin/bash'):
    _validate_name(name)
    import pwd
    try:
        pwd.getpwnam(name)
        raise ValueError('User already exists: ' + name)
    except KeyError:
        pass
    if shutil.which('useradd') is None:
        raise ValueError('useradd is required (shadow suite)')
    run('useradd', '-m', '-s', shell, name)
    print('User created: ' + name)


def _sudo_file(name, sudo_dir):
    _validate_name(name)
    sudo_dir = Path(sudo_dir)
    if sudo_dir.is_symlink():
        raise ValueError('Symlink sudoers directory refused')
    return sudo_dir / (SUDO_PREFIX + name)


def sudo_grant(name, sudo_dir=Path('/etc/sudoers.d'), nopasswd=False):
    entry = _lookup(name)
    if entry.pw_uid == 0:
        raise ValueError('root already holds full privileges')
    if entry.pw_uid < 1000:
        raise ValueError('Refusing to grant sudo to a system account (uid < 1000)')
    if shutil.which('visudo') is None:
        raise ValueError('visudo is required (sudo package)')
    sudo_dir = Path(sudo_dir)
    if not sudo_dir.is_dir():
        raise ValueError('sudoers include directory missing: ' + str(sudo_dir))
    target = _sudo_file(name, sudo_dir)
    original = None
    saved = None
    if target.exists():
        regular(target)
        original = target.read_text()
        if not original.startswith(SUDO_MARKER):
            raise ValueError('Unknown sudoers entry; refusing overwrite')
        saved = backup(target)
    privilege = 'ALL=(ALL:ALL) NOPASSWD:ALL' if nopasswd else 'ALL=(ALL:ALL) ALL'
    content = SUDO_MARKER + name + ' ' + privilege + '\n'
    with tempfile.TemporaryDirectory(prefix='fusionbox-sudo-') as temporary:
        staged = Path(temporary) / target.name
        staged.write_text(content)
        os.chmod(staged, 0o440)
        run('visudo', '-c', '-f', str(staged))
    try:
        replace(target, content, saved)
        os.chmod(target, 0o440)
        if os.geteuid() == 0:
            os.chown(target, 0, 0)
        run('visudo', '-c', '-f', str(target))
    except Exception:
        if original is None:
            target.unlink(missing_ok=True)
        else:
            replace(target, original, saved)
            os.chmod(target, 0o440)
            if os.geteuid() == 0:
                os.chown(target, 0, 0)
        raise
    print('Managed sudoers entry installed and validated; sudo group membership untouched.')


def sudo_revoke(name, sudo_dir=Path('/etc/sudoers.d')):
    target = _sudo_file(name, sudo_dir)
    if not target.exists():
        raise ValueError('No FusionBox managed sudo entry for ' + name)
    regular(target)
    if not target.read_text().startswith(SUDO_MARKER):
        raise ValueError('Unknown sudoers entry; refusing deletion')
    target.unlink()
    print('Managed sudoers entry removed; all other sudo configuration untouched.')


def user_del(name, sudo_dir=Path('/etc/sudoers.d')):
    _validate_name(name)
    entry = _lookup(name)
    if entry.pw_uid == 0:
        raise ValueError('Refusing to delete root')
    if entry.pw_uid < 1000:
        raise ValueError('Refusing to delete a system account (uid < 1000)')
    target = _sudo_file(name, sudo_dir)
    if target.exists():
        regular(target)
        if not target.read_text().startswith(SUDO_MARKER):
            raise ValueError('Unknown sudoers entry for user; manual review required')
    if shutil.which('userdel') is None:
        raise ValueError('userdel is required (shadow suite)')
    try:
        run('userdel', '-r', name)
    except subprocess.CalledProcessError:
        raise ValueError('userdel failed - the account may still have active '
                         'sessions or processes; log out and retry')
    if target.exists():
        target.unlink()
    print('User and home directory removed; managed sudo entry removed.')


def passwd_set(name, password):
    _validate_name(name)
    if not password or ':' in password or '\n' in password or '\r' in password or len(password) > 512:
        raise ValueError('Password must be non-empty without colon/newline (max 512 chars)')
    entry = _lookup(name)
    if entry.pw_uid == 0:
        print('Changing root password affects SSH password login for root.')
    subprocess.run(['chpasswd'], input=name + ':' + password + '\n', check=True,
                   text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print('Password updated for ' + name)


def user_key_install(name, key_line):
    _validate_name(name)
    entry = _lookup(name)
    home = Path(entry.pw_dir)
    uid, gid = entry.pw_uid, entry.pw_gid
    ssh_dir = home / '.ssh'
    authorized = ssh_dir / 'authorized_keys'
    if not home.is_dir() or home.stat().st_uid != uid:
        raise ValueError('Home directory is missing or not owned by ' + name)
    if home.is_symlink() or ssh_dir.is_symlink() or authorized.is_symlink():
        raise ValueError('Symlink path refused')
    if key_line != key_line.strip() or '\n' in key_line or '\r' in key_line:
        raise ValueError('Public key must be a single trimmed line')
    with tempfile.TemporaryDirectory(prefix='fusionbox-ukey-') as temporary:
        candidate = Path(temporary) / 'key.pub'
        candidate.write_text(key_line + '\n')
        if len(valid_keys(candidate)) != 1:
            raise ValueError('Invalid plain public key')
    if ssh_dir.exists():
        st = ssh_dir.stat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != uid:
            raise ValueError('.ssh exists but is not a directory owned by ' + name)
    else:
        ssh_dir.mkdir(mode=0o700)
        os.chown(ssh_dir, uid, gid)
    saved = None
    if authorized.exists():
        st = authorized.stat()
        if not stat.S_ISREG(st.st_mode) or st.st_uid != uid:
            raise ValueError('authorized_keys exists but is not a regular file owned by ' + name)
        saved = backup(authorized)
        content = authorized.read_text().rstrip('\n') + '\n' + key_line + '\n'
        replace(authorized, content, saved)
    else:
        replace(authorized, key_line + '\n')
    os.chown(authorized, uid, gid)
    os.chmod(authorized, 0o600)
    print('Public key installed for ' + name + ' (authorized_keys 0600, .ssh 0700).')


def f2b_unban(ip):
    import ipaddress
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        raise ValueError('Invalid IP address: ' + ip)
    try:
        run('fail2ban-client', 'set', 'sshd', 'unbanip', ip)
    except subprocess.CalledProcessError:
        raise ValueError('fail2ban rejected unban for ' + ip +
                         ' (not banned, or sshd jail missing)')
    print('Unban processed for ' + ip + ' (no longer in the banned list).')


def f2b_uninstall(directory=Path('/etc/fail2ban')):
    target = Path(directory) / 'jail.d/99-fusionbox-sshd.local'
    if target.exists():
        regular(target)
        if not target.read_text().startswith('# FusionBox managed sshd parameters v1\n'):
            raise ValueError('Unknown jail.d file; refusing removal')
    subprocess.run(['systemctl', 'disable', '--now', 'fail2ban'], check=False,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if target.exists():
        target.unlink()
    print('Service disabled and FusionBox jail parameters removed; '
          'package removal and remaining /etc/fail2ban files are handled separately.')


LOGIN_MARKER = '# FusionBox managed SSH login alert v1\n'
LOGIN_CONTROL = '[success=ok default=ignore]'
LOGIN_COMMAND = ('session ' + LOGIN_CONTROL +
                 ' pam_exec.so quiet /usr/local/bin/fusionbox-login-alert\n')
LOGIN_SCRIPT_MARKER = '# FusionBox managed SSH login alert script v1\n'


def _sha256(data):
    if isinstance(data, str):
        data = data.encode()
    return hashlib.sha256(data).hexdigest()


def _managed_record(path, content):
    return {'path': str(path), 'content': base64.b64encode(content.encode()).decode(),
            'sha256': _sha256(content)}


def _managed_matches(path, record):
    return (path.is_file() and not path.is_symlink() and
            _sha256(path.read_bytes()) == record.get('sha256') and
            path.read_bytes() == base64.b64decode(record.get('content', '')))


def _validate_managed(path, record, purpose):
    if record is None:
        if path.exists():
            raise ValueError('Unexpected managed path; refusing ' + purpose + ': ' + str(path))
    elif not _managed_matches(path, record):
        raise ValueError('Managed file drift; refusing ' + purpose + ': ' + str(path))


def _thp_current(path):
    if not path.exists():
        return None
    matches = re.findall(r'\[([^\[\]\s]+)\]', path.read_text())
    if len(matches) != 1:
        raise ValueError('Expected exactly one active THP mode')
    return matches[0]


def _unit_state(unit_file):
    unit_file = Path(unit_file)
    if not unit_file.exists():
        return {'exists': False}
    state = {'exists': True, 'enabled': False, 'active': False}
    if shutil.which('systemctl'):
        state.update({
            'enabled': subprocess.run(['systemctl', 'is-enabled', '--quiet', 'fusionbox-thp.service'],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0,
            'active': subprocess.run(['systemctl', 'is-active', '--quiet', 'fusionbox-thp.service'],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0,
        })
    return state


def _restore_unit_state(saved, unit_file):
    if saved is None:
        return
    unit_file = Path(unit_file)
    if not saved['exists']:
        if not unit_file.exists() and not unit_file.is_symlink():
            return
        if shutil.which('systemctl'):
            subprocess.run(['systemctl', 'disable', '--now', 'fusionbox-thp.service'],
                           check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            run('systemctl', 'daemon-reload')
            active = subprocess.run(['systemctl', 'is-active', '--quiet', 'fusionbox-thp.service'],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0
            enabled = subprocess.run(['systemctl', 'is-enabled', '--quiet', 'fusionbox-thp.service'],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0
            if active or enabled:
                raise ValueError('THP service remained active or enabled after restore')
        unit_file.unlink(missing_ok=True)
        if shutil.which('systemctl'):
            run('systemctl', 'daemon-reload')
        return
    if not unit_file.exists():
        raise ValueError('THP unit file missing during state restore')
    if not shutil.which('systemctl'):
        if saved['enabled'] or saved['active']:
            raise ValueError('systemctl required to restore THP unit state')
        return
    run('systemctl', 'daemon-reload')
    run('systemctl', 'enable' if saved['enabled'] else 'disable',
        'fusionbox-thp.service')
    run('systemctl', 'start' if saved['active'] else 'stop',
        'fusionbox-thp.service')
    if _unit_state(unit_file) != saved:
        raise ValueError('systemd unit state restore validation failed')


def _owned_path(path, mode=None):
    path = Path(path)
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError('Symlink path refused: ' + str(path))
    if path.exists():
        st = regular(path)
        if st.st_uid != 0 and os.geteuid() == 0:
            raise ValueError('Root ownership required: ' + str(path))
        if mode is not None and stat.S_IMODE(st.st_mode) != mode:
            raise ValueError('Unexpected permissions on ' + str(path))
    return path


def _login_script(conf_path='/etc/fusionbox/notify.conf'):
    conf_path = str(conf_path).replace("'", "'\\''")
    return '''#!/bin/bash
''' + LOGIN_SCRIPT_MARKER + '''set +x
umask 077
[[ "${1:-}" == "--test" || "${PAM_TYPE:-}" == "open_session" ]] || exit 0
CONF=''' + "'" + conf_path + "'" + '''
[[ -f "$CONF" && ! -L "$CONF" ]] || exit 0
perm=$(stat -c '%u %a' "$CONF" 2>/dev/null) || exit 0
[[ "$perm" == "0 600" || "$perm" == "0 400" ]] || exit 0
get_conf() { sed -n "s/^[[:space:]]*$1=//p" "$CONF" | tail -1 | tr -d '\"' | tr -d "'" | tr -d '\\r'; }
token=$(get_conf TG_BOT_TOKEN)
chat=$(get_conf TG_CHAT_ID)
[[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ && "$chat" =~ ^-?[0-9]+$ ]] || exit 0
if [[ "${1:-}" == "--test" ]]; then
  user=${SUDO_USER:-root}; source_ip=test
else
  user=${PAM_USER:-unknown}; source_ip=${PAM_RHOST:-local}
fi
user=${user//[^A-Za-z0-9_.@-]/_}
source_ip=${source_ip//[^A-Fa-f0-9:._-]/_}
text="[FusionBox] SSH login user=$user source=$source_ip time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
response=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\\ndata-urlencode = "chat_id=%s"\\n' "$token" "$chat" |
  curl -q -fsS --max-time 5 --config - --data-urlencode "text=$text" 2>/dev/null) || exit 0
printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not isinstance(d,dict) or d.get("ok") is not True)' 2>/dev/null || true
exit 0
'''


def login_alert(action, pam=Path('/etc/pam.d/sshd'),
                script=Path('/usr/local/bin/fusionbox-login-alert'),
                conf=Path('/etc/fusionbox/notify.conf'),
                state_file=Path('/var/lib/fusionbox/login-alert.json')):
    pam, script, conf, state_file = map(Path, (pam, script, conf, state_file))
    block = LOGIN_MARKER + LOGIN_COMMAND
    state = None
    if state_file.exists():
        _owned_path(state_file, 0o600)
        state = json.loads(state_file.read_text())
    if action == 'status':
        installed = bool(state and _managed_matches(script, state.get('script')) and
                         _managed_matches(pam, state.get('pam')))
        print('installed' if installed else 'not-installed')
        return
    if action == 'test':
        if not state:
            raise ValueError('Managed login alert is not installed')
        _validate_managed(script, state.get('script'), 'test')
        _validate_managed(pam, state.get('pam'), 'test')
        subprocess.run([str(script), '--test'], check=True)
        print('Test notification dispatched (transport failures never affect login).')
        return
    _owned_path(pam)
    if not pam.exists():
        raise ValueError('OpenSSH PAM service file missing: ' + str(pam))
    original_pam = pam.read_text()
    if action == 'uninstall':
        if not state:
            raise ValueError('Managed login alert state missing; refusing removal')
        _validate_managed(script, state.get('script'), 'removal')
        _validate_managed(pam, state.get('pam'), 'removal')
        replace(pam, base64.b64decode(state['pam_original']).decode())
        script.unlink()
        state_file.unlink()
        print('SSH login alert removed; Telegram configuration preserved.')
        return
    if action != 'install':
        raise ValueError('Expected install, status, test or uninstall')
    _owned_path(conf, 0o600)
    if not conf.exists():
        raise ValueError('Telegram configuration missing: ' + str(conf))
    values = dict(re.findall(r'^\s*(TG_BOT_TOKEN|TG_CHAT_ID)=([^\r\n]+)', conf.read_text(), re.M))
    token = values.get('TG_BOT_TOKEN', '').strip('"\'')
    chat = values.get('TG_CHAT_ID', '').strip('"\'')
    if not re.fullmatch(r'[0-9]+:[A-Za-z0-9_-]+', token) or not re.fullmatch(r'-?[0-9]+', chat):
        raise ValueError('Telegram credentials are missing or invalid')
    if state:
        _validate_managed(script, state.get('script'), 'overwrite')
        _validate_managed(pam, state.get('pam'), 'overwrite')
        pam_original = state['pam_original']
    else:
        if script.exists():
            raise ValueError('Existing login alert script refused: ' + str(script))
        if LOGIN_MARKER in original_pam:
            raise ValueError('Untracked PAM block refused')
        pam_original = base64.b64encode(original_pam.encode()).decode()
    script_content = _login_script(conf)
    pam_content = original_pam if block in original_pam else original_pam.rstrip('\n') + '\n' + block
    record = {'version': 1, 'pam_original': pam_original,
              'script': _managed_record(script, script_content),
              'pam': _managed_record(pam, pam_content)}
    original_script = script.read_bytes() if script.exists() else None
    original_state = state_file.read_bytes() if state_file.exists() else None
    try:
        script.parent.mkdir(parents=True, exist_ok=True)
        state_file.parent.mkdir(parents=True, exist_ok=True)
        replace(script, script_content)
        os.chmod(script, 0o755)
        if os.geteuid() == 0:
            os.chown(script, 0, 0)
        replace(pam, pam_content)
        if not shutil.which('sshd'):
            raise ValueError('sshd is required for configuration validation')
        run('sshd', '-t')
        replace(state_file, json.dumps(record, sort_keys=True) + '\n')
        os.chmod(state_file, 0o600)
        if os.geteuid() == 0:
            os.chown(state_file, 0, 0)
    except Exception:
        replace(pam, original_pam)
        if original_script is None:
            script.unlink(missing_ok=True)
        else:
            replace(script, original_script.decode())
            os.chmod(script, 0o755)
        if original_state is None:
            state_file.unlink(missing_ok=True)
        else:
            replace(state_file, original_state.decode())
            os.chmod(state_file, 0o600)
        raise
    print('SSH login alert installed with explicit PAM ignore-on-failure control.')


TUNING_MARKER = '# FusionBox managed kernel tuning v1\n'
TUNING_PROFILES = {
    'balanced': {'swappiness': 10, 'dirty_bg': 10, 'dirty': 20, 'somax': 4096, 'backlog': 4096, 'syn': 4096, 'map': 262144, 'nofile': 262144, 'nproc': 65535, 'thp': 'madvise'},
    'high': {'swappiness': 10, 'dirty_bg': 5, 'dirty': 15, 'somax': 16384, 'backlog': 32768, 'syn': 16384, 'map': 524288, 'nofile': 1048576, 'nproc': 131072, 'thp': 'madvise'},
    'web': {'swappiness': 10, 'dirty_bg': 5, 'dirty': 15, 'somax': 8192, 'backlog': 16384, 'syn': 8192, 'map': 262144, 'nofile': 524288, 'nproc': 65535, 'thp': 'madvise'},
    'stream': {'swappiness': 10, 'dirty_bg': 5, 'dirty': 20, 'somax': 8192, 'backlog': 32768, 'syn': 8192, 'map': 262144, 'nofile': 524288, 'nproc': 65535, 'thp': 'madvise'},
    'game': {'swappiness': 5, 'dirty_bg': 5, 'dirty': 10, 'somax': 4096, 'backlog': 8192, 'syn': 4096, 'map': 262144, 'nofile': 262144, 'nproc': 65535, 'thp': 'never'},
    'db': {'swappiness': 1, 'dirty_bg': 5, 'dirty': 15, 'somax': 4096, 'backlog': 8192, 'syn': 4096, 'map': 1048576, 'nofile': 524288, 'nproc': 65535, 'thp': 'never'},
}


def _sysctl_get(key):
    return run('sysctl', '-n', key).strip()


def _tuning_values(profile, ram_kib):
    p = TUNING_PROFILES[profile]
    values = {
        'vm.swappiness': str(p['swappiness']), 'vm.dirty_background_ratio': str(p['dirty_bg']),
        'vm.dirty_ratio': str(p['dirty']), 'vm.max_map_count': str(p['map']),
        'fs.file-max': str(max(p['nofile'] * 2, 524288)), 'net.core.somaxconn': str(p['somax']),
        'net.core.netdev_max_backlog': str(p['backlog']), 'net.ipv4.tcp_max_syn_backlog': str(p['syn']),
        'net.ipv4.tcp_fastopen': '3', 'net.ipv4.tcp_tw_reuse': '1',
    }
    if ram_kib and ram_kib < 2 * 1024 * 1024:
        values['vm.max_map_count'] = str(min(int(values['vm.max_map_count']), 262144))
        values['fs.file-max'] = str(min(int(values['fs.file-max']), 524288))
    if profile == 'stream':
        buf = 16777216 if ram_kib and ram_kib < 4 * 1024 * 1024 else 67108864
        values.update({'net.core.rmem_max': str(buf), 'net.core.wmem_max': str(buf),
                       'net.ipv4.tcp_rmem': '4096 262144 ' + str(buf),
                       'net.ipv4.tcp_wmem': '4096 262144 ' + str(buf)})
    return values


def _file_snapshot(path):
    if not path.exists():
        return None
    _owned_path(path)
    return {'content': base64.b64encode(path.read_bytes()).decode(),
            'mode': stat.S_IMODE(path.stat().st_mode)}


def _restore_file(path, saved):
    if saved is None:
        path.unlink(missing_ok=True)
    else:
        replace(path, base64.b64decode(saved['content']).decode())
        os.chmod(path, saved['mode'])


def _restore_components(runtime, files, thp_path, thp_mode, unit_state, unit_file,
                        state_dir):
    errors = []
    rollback = state_dir / '.rollback.conf'
    try:
        replace(rollback, ''.join(f'{k} = {v}\n' for k, v in runtime.items()))
        run('sysctl', '-p', str(rollback))
    except Exception as error:
        errors.append('sysctl: ' + str(error))
    finally:
        rollback.unlink(missing_ok=True)
    for path, saved in files.items():
        try:
            _restore_file(Path(path), saved)
        except Exception as error:
            errors.append(str(path) + ': ' + str(error))
    if thp_mode is not None and thp_path.exists():
        try:
            thp_path.write_text(thp_mode)
            if _thp_current(thp_path) != thp_mode:
                raise ValueError('THP restore validation failed')
        except Exception as error:
            errors.append('THP: ' + str(error))
    try:
        _restore_unit_state(unit_state, unit_file)
    except Exception as error:
        errors.append('systemd: ' + str(error))
    if errors:
        raise RuntimeError('Rollback incomplete: ' + '; '.join(errors))


def tuning(action, profile=None, etc=Path('/etc'), state_dir=Path('/var/lib/fusionbox/tuning'),
           thp=Path('/sys/kernel/mm/transparent_hugepage/enabled')):
    etc, state_dir, thp = Path(etc), Path(state_dir), Path(thp)
    sysctl_file = etc / 'sysctl.d/99-fusionbox-tuning.conf'
    limits_file = etc / 'security/limits.d/99-fusionbox-tuning.conf'
    unit_file = etc / 'systemd/system/fusionbox-thp.service'
    state_file = state_dir / 'snapshot.json'
    managed = (sysctl_file, limits_file, unit_file)
    if action == 'status':
        active = state_file.is_file() and sysctl_file.is_file()
        selected = 'unknown'
        if active:
            try:
                selected = json.loads(state_file.read_text()).get('profile', 'unknown')
            except (OSError, ValueError):
                selected = 'invalid-state'
        print(('active ' + selected) if active else 'not-active')
        return
    if action == 'restore':
        if not state_file.exists():
            raise ValueError('No tuning snapshot; refusing to claim restoration')
        state = json.loads(state_file.read_text())
        expected = state.get('managed', {})
        for path in managed:
            _validate_managed(path, expected.get(str(path)), 'restore')
        runtime_before = {key: _sysctl_get(key) for key in state['sysctl']}
        files_before = {str(path): _file_snapshot(path) for path in managed}
        thp_before = _thp_current(thp)
        unit_before = _unit_state(unit_file)
        try:
            restore_conf = state_dir / '.restore.conf'
            replace(restore_conf, ''.join(f'{k} = {v}\n' for k, v in state['sysctl'].items()))
            run('sysctl', '-p', str(restore_conf))
            restore_conf.unlink(missing_ok=True)
            for path in managed:
                _restore_file(path, state['files'][str(path)])
            if state.get('thp') is not None and thp.exists():
                thp.write_text(state['thp'])
                if _thp_current(thp) != state['thp']:
                    raise ValueError('THP restore validation failed')
            _restore_unit_state(state.get('unit_state'), unit_file)
        except Exception as error:
            try:
                _restore_components(runtime_before, files_before, thp, thp_before,
                                    unit_before, unit_file, state_dir)
            except Exception as rollback_error:
                raise RuntimeError(str(error) + '; ' + str(rollback_error)) from error
            raise
        state_file.unlink()
        print('Kernel tuning runtime values, THP state and managed files restored from snapshot.')
        return
    if action != 'apply' or profile not in TUNING_PROFILES:
        raise ValueError('Tuning profile must be one of: ' + ', '.join(TUNING_PROFILES))
    for path in managed:
        if path.exists() and not path.read_text().startswith(TUNING_MARKER):
            raise ValueError('Existing external file refused: ' + str(path))
    ram_kib = 0
    try:
        match = re.search(r'^MemTotal:\s+(\d+)', Path('/proc/meminfo').read_text(), re.M)
        ram_kib = int(match.group(1)) if match else 0
    except (OSError, ValueError):
        pass
    requested = _tuning_values(profile, ram_kib)
    supported = {}
    for key, value in requested.items():
        try:
            _sysctl_get(key)
            supported[key] = value
        except subprocess.SubprocessError:
            pass
    if not supported:
        raise ValueError('No requested sysctl keys are supported by this kernel')
    state_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(state_dir, 0o700)
    first = not state_file.exists()
    previous_snapshot = state_file.read_bytes() if not first else None
    if first:
        state = {'version': 2, 'profile': profile,
                 'sysctl': {key: _sysctl_get(key) for key in supported},
                 'files': {str(path): _file_snapshot(path) for path in managed},
                 'thp': _thp_current(thp), 'unit_state': _unit_state(unit_file), 'managed': {}}
    else:
        state = json.loads(state_file.read_text())
        for path in managed:
            _validate_managed(path, state.get('managed', {}).get(str(path)), 'overwrite')
        state['profile'] = profile
        for key in supported:
            if key not in state['sysctl']:
                state['sysctl'][key] = _sysctl_get(key)
    before = {key: _sysctl_get(key) for key in supported}
    previous_files = {str(path): _file_snapshot(path) for path in managed}
    previous_thp = _thp_current(thp)
    previous_unit = _unit_state(unit_file)
    p = TUNING_PROFILES[profile]
    sysctl_content = TUNING_MARKER + '# profile: ' + profile + '\n' + ''.join(f'{k} = {v}\n' for k, v in sorted(supported.items()))
    limits_content = (TUNING_MARKER + '# profile: ' + profile + '\n' +
                      f'* soft nofile {p["nofile"]}\n* hard nofile {p["nofile"]}\n' +
                      f'* soft nproc {p["nproc"]}\n* hard nproc {p["nproc"]}\n')
    unit_content = (TUNING_MARKER + '[Unit]\nDescription=FusionBox transparent hugepage policy\nAfter=sysinit.target\n\n'
                    '[Service]\nType=oneshot\nExecStart=/bin/sh -c \'echo ' + p['thp'] + ' > /sys/kernel/mm/transparent_hugepage/enabled\'\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n')
    expected_content = {sysctl_file: sysctl_content, limits_file: limits_content}
    if thp.exists() and shutil.which('systemctl'):
        expected_content[unit_file] = unit_content
    state['managed'] = {str(path): (_managed_record(path, expected_content[path])
                                   if path in expected_content else None)
                        for path in managed}
    replace(state_file, json.dumps(state, sort_keys=True) + '\n')
    os.chmod(state_file, 0o600)
    try:
        for path, content in ((sysctl_file, sysctl_content), (limits_file, limits_content)):
            path.parent.mkdir(parents=True, exist_ok=True)
            replace(path, content)
            os.chmod(path, 0o644)
        run('sysctl', '-p', str(sysctl_file))
        for key, expected in supported.items():
            if ' '.join(_sysctl_get(key).split()) != ' '.join(expected.split()):
                raise ValueError('sysctl validation failed for ' + key)
        if thp.exists() and shutil.which('systemctl'):
            unit_file.parent.mkdir(parents=True, exist_ok=True)
            replace(unit_file, unit_content)
            os.chmod(unit_file, 0o644)
            run('systemctl', 'daemon-reload')
            run('systemctl', 'enable', '--now', 'fusionbox-thp.service')
            if _thp_current(thp) != p['thp']:
                raise ValueError('THP policy validation failed')
    except Exception as error:
        try:
            _restore_components(before, previous_files, thp, previous_thp,
                                previous_unit, unit_file, state_dir)
        except Exception as rollback_error:
            if first:
                state_file.unlink(missing_ok=True)
            else:
                replace(state_file, previous_snapshot.decode())
                os.chmod(state_file, 0o600)
            raise RuntimeError(str(error) + '; ' + str(rollback_error)) from error
        if first:
            state_file.unlink(missing_ok=True)
        else:
            replace(state_file, previous_snapshot.decode())
            os.chmod(state_file, 0o600)
        raise

    print(f'Applied {profile} tuning with {len(supported)} supported sysctl keys; snapshot retained for restore.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['keys-add', 'keys-list', 'keys-check', 'keys-delete', 'ssh', 'ssh-preflight', 'swap', 'fail2ban',
                                           'user-add', 'user-del', 'passwd-set', 'sudo-grant', 'sudo-revoke', 'user-key-install',
                                           'f2b-unban', 'f2b-uninstall', 'login-alert', 'tuning'])
    parser.add_argument('values', nargs='*')
    args = parser.parse_args()
    try:
        if args.action == 'keys-add':
            keys_add(Path.home() / '.ssh/authorized_keys', sys.stdin.readline().rstrip('\n'))
        elif args.action.startswith('keys-'):
            keys_action(Path.home() / '.ssh/authorized_keys', args.action[5:],
                        int(args.values[0]) if args.values else None)
        elif args.action == 'ssh-preflight':
            if args.values:
                raise ValueError('ssh-preflight takes no arguments')
            ssh_preflight()
        elif args.action == 'ssh':
            ssh_change(Path('/etc/ssh/sshd_config'), *args.values)
        elif args.action == 'swap':
            swap_remove(Path('/swapfile'), Path('/etc/fstab'))
        elif args.action == 'fail2ban':
            fail2ban_change(Path('/etc/fail2ban'), *args.values)
        elif args.action == 'user-add':
            if len(args.values) > 2:
                raise ValueError('user-add takes a name and optional shell')
            user_add(args.values[0] if args.values else '', args.values[1] if len(args.values) > 1 else '/bin/bash')
        elif args.action == 'user-del':
            user_del(args.values[0] if args.values else '')
        elif args.action == 'passwd-set':
            if len(args.values) != 1:
                raise ValueError('passwd-set takes exactly one username')
            passwd_set(args.values[0], sys.stdin.readline().rstrip('\n'))
        elif args.action == 'sudo-grant':
            if not args.values or len(args.values) > 2 or (len(args.values) == 2 and args.values[1] != 'nopasswd'):
                raise ValueError('sudo-grant takes a username and optional "nopasswd"')
            sudo_grant(args.values[0], Path('/etc/sudoers.d'),
                       len(args.values) == 2 and args.values[1] == 'nopasswd')
        elif args.action == 'sudo-revoke':
            if len(args.values) != 1:
                raise ValueError('sudo-revoke takes exactly one username')
            sudo_revoke(args.values[0])
        elif args.action == 'user-key-install':
            if len(args.values) != 1:
                raise ValueError('user-key-install takes exactly one username')
            user_key_install(args.values[0], sys.stdin.readline().rstrip('\n'))
        elif args.action == 'f2b-unban':
            if len(args.values) != 1:
                raise ValueError('f2b-unban takes exactly one IP address')
            f2b_unban(args.values[0])
        elif args.action == 'f2b-uninstall':
            f2b_uninstall()
        elif args.action == 'login-alert':
            if len(args.values) != 1:
                raise ValueError('login-alert takes install, status, test or uninstall')
            login_alert(args.values[0])
        elif args.action == 'tuning':
            if not args.values or len(args.values) > 2:
                raise ValueError('tuning takes apply PROFILE, status, or restore')
            tuning(args.values[0], args.values[1] if len(args.values) == 2 else None)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Do not print command output; daemon diagnostics may contain secrets.
        print('Operation failed: ' + (str(error) if not isinstance(error, subprocess.SubprocessError) else 'command validation/activation failed'))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
