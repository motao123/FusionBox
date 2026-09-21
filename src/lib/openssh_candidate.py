"""Build and exercise an isolated, signed OpenSSH candidate.

This module never edits the distribution sshd, its configuration, systemd units,
or production listeners. Every generated file lives below the owned candidate
state directory and the test daemon uses a fixed loopback high port.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request


OPENSSH_VERSION = "10.5p1"
TARBALL_NAME = f"openssh-{OPENSSH_VERSION}.tar.gz"
SIGNATURE_NAME = f"{TARBALL_NAME}.asc"
SOURCE_URL = f"https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/{TARBALL_NAME}"
SIGNATURE_URL = f"https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/{SIGNATURE_NAME}"
RELEASE_KEY_URL = "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/RELEASE_KEY.asc"
TARBALL_SHA256 = "d44d28a839ea9daf969cc69150fde59910b2b39361dad81a3bd6cbd19218db11"
RELEASE_KEY_FINGERPRINT = "7168B983815A5EEF59A4ADFD2A3F414E736060BA"
OWNER_MARKER = "fusionbox-openssh-candidate-v1"
DEFAULT_STATE_DIR = Path("/var/lib/fusionbox/openssh-candidate")
DEFAULT_PORT = 50222
MAX_TARBALL_BYTES = 64 * 1024 * 1024
MAX_SIGNATURE_BYTES = 1024 * 1024
MAX_KEY_BYTES = 1024 * 1024

# Production-side defaults. Every one of them can be pointed elsewhere explicitly
# on the command line, which is how the acceptance fixture exercises the whole
# switch transaction against a disposable daemon instead of the access path.
SSHD_BINARY = "/usr/sbin/sshd"
SSHD_CONFIG = "/etc/ssh/sshd_config"
SSHD_PIDFILE = "/run/sshd.pid"
SSHD_RELOAD = "systemctl reload ssh.service"
SSHD_RESTART = "systemctl restart ssh.service"
# Effective values compared between the running daemon and the candidate. A
# difference means the switch would silently change authentication policy, which
# is refused unless the operator explicitly accepts the drift.
SECURITY_KEYS = (
    "port", "listenaddress", "permitrootlogin", "passwordauthentication",
    "pubkeyauthentication", "kbdinteractiveauthentication",
    "challengeresponseauthentication", "permitemptypasswords",
    "authorizedkeysfile", "usepam", "hostkey", "subsystem", "allowusers",
)
WATCHDOG_GRACE = 60
# How long the post-reload probe waits for the re-executed daemon to accept again.
SWITCH_PROBE_TIMEOUT = 20
SWITCH_STATUSES = ("verifying", "verified", "rolled-back", "auto-rolled-back")


class CandidateError(ValueError):
    pass


def _run(args, cwd=None, capture=True, timeout=300):
    result = subprocess.run(
        [str(arg) for arg in args], cwd=str(cwd) if cwd else None,
        check=False, text=True, stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None, timeout=timeout)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "command failed").strip()
        raise CandidateError(f"{Path(str(args[0])).name} failed: {detail[-1200:]}")
    return result


def _regular(path, maximum=None):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise CandidateError(f"Expected a regular candidate file: {path}")
    st = path.stat()
    if st.st_nlink != 1:
        raise CandidateError(f"Multiple-link candidate file refused: {path}")
    if maximum is not None and st.st_size > maximum:
        raise CandidateError(f"Candidate file exceeds size limit: {path}")
    return st


def _ensure_directory(path, mode=0o700):
    path = Path(path)
    if path.exists() and path.is_symlink():
        raise CandidateError(f"Symlink candidate directory refused: {path}")
    path.mkdir(parents=True, exist_ok=True, mode=mode)
    if not path.is_dir():
        raise CandidateError(f"Candidate path is not a directory: {path}")
    os.chmod(path, mode)
    return path


def _state_dir(value, create=False):
    path = Path(value).expanduser()
    if path.is_symlink():
        raise CandidateError("Candidate state directory cannot be a symlink")
    if create:
        _ensure_directory(path)
    elif not path.exists():
        return path
    if not path.is_dir():
        raise CandidateError("Candidate state path is not a directory")
    return path


def _marker_path(state):
    return state / ".owner"


def _claim_state(state):
    _ensure_directory(state)
    marker = _marker_path(state)
    if marker.exists():
        _regular(marker, 256)
        if marker.read_text(encoding="ascii") != OWNER_MARKER + "\n":
            raise CandidateError("Candidate state directory belongs to another owner")
        return
    if marker.is_symlink():
        raise CandidateError("Candidate owner marker is a symlink")
    fd, temporary = tempfile.mkstemp(prefix=".owner.", dir=state)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            stream.write(OWNER_MARKER + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, marker)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _atomic_write(path, data, mode=0o600):
    path = Path(path)
    _ensure_directory(path.parent)
    if path.is_symlink():
        raise CandidateError(f"Symlink candidate output refused: {path}")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _open_url(url, limit):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, response, code, msg, headers, newurl):
            raise CandidateError(f"Unexpected redirect while fetching official source: {url}")

    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, headers={"User-Agent": "FusionBox-OpenSSH-Candidate/1"})
    try:
        response = opener.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        raise CandidateError(f"Official source request failed: HTTP {error.code}") from error
    except (urllib.error.URLError, OSError) as error:
        raise CandidateError(f"Official source request failed: {error}") from error
    with contextlib.closing(response):
        chunks = []
        total = 0
        while True:
            chunk = response.read(min(1024 * 1024, limit - total + 1))
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise CandidateError(f"Official source exceeds {limit} byte limit")
            chunks.append(chunk)
    return b"".join(chunks)


def _download_sources(state):
    source = _ensure_directory(state / "source")
    _atomic_write(source / TARBALL_NAME, _open_url(SOURCE_URL, MAX_TARBALL_BYTES), 0o600)
    _atomic_write(source / SIGNATURE_NAME, _open_url(SIGNATURE_URL, MAX_SIGNATURE_BYTES), 0o600)
    _atomic_write(source / "RELEASE_KEY.asc", _open_url(RELEASE_KEY_URL, MAX_KEY_BYTES), 0o600)


def _gpg_verify(tarball, signature, key):
    gpg = shutil.which("gpg")
    if not gpg:
        raise CandidateError("gpg is required for the official OpenSSH signature")
    with tempfile.TemporaryDirectory(prefix="fusionbox-gpg-") as home:
        os.chmod(home, 0o700)
        _run([gpg, "--batch", "--homedir", home, "--import", str(key)], timeout=30)
        listed = _run([
            gpg, "--batch", "--homedir", home, "--with-colons", "--list-keys"], timeout=30)
        fingerprints = {
            line.split(":")[9].upper()
            for line in listed.stdout.splitlines()
            if line.startswith("fpr:") and len(line.split(":")) > 9
        }
        if RELEASE_KEY_FINGERPRINT not in fingerprints:
            raise CandidateError("Official release key fingerprint mismatch")
        verified = _run([
            gpg, "--batch", "--homedir", home, "--status-fd", "1", "--verify",
            str(signature), str(tarball)], timeout=30)
        valid = [
            line.split()[2].upper()
            for line in verified.stdout.splitlines()
            if line.startswith("[GNUPG:] VALIDSIG ") and len(line.split()) > 2
        ]
        if RELEASE_KEY_FINGERPRINT not in valid:
            raise CandidateError("OpenSSH signature is not from the pinned release key")


def verify_sources(state):
    source = state / "source"
    tarball = source / TARBALL_NAME
    signature = source / SIGNATURE_NAME
    key = source / "RELEASE_KEY.asc"
    _regular(tarball, MAX_TARBALL_BYTES)
    _regular(signature, MAX_SIGNATURE_BYTES)
    _regular(key, MAX_KEY_BYTES)
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    if digest != TARBALL_SHA256:
        raise CandidateError(f"OpenSSH SHA256 mismatch: {digest}")
    _gpg_verify(tarball, signature, key)
    record = {
        "owner": OWNER_MARKER,
        "version": OPENSSH_VERSION,
        "tarball": TARBALL_NAME,
        "sha256": digest,
        "release_key_fingerprint": RELEASE_KEY_FINGERPRINT,
        "source_url": SOURCE_URL,
        "verified": True,
    }
    _atomic_write(state / "verification.json", (json.dumps(record, sort_keys=True) + "\n").encode())
    return record


def _load_verification(state):
    path = state / "verification.json"
    _regular(path, 8192)
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CandidateError("Invalid candidate verification record") from error
    if (record.get("owner") != OWNER_MARKER or record.get("version") != OPENSSH_VERSION or
            record.get("sha256") != TARBALL_SHA256 or record.get("verified") is not True):
        raise CandidateError("Candidate verification record does not match the pinned source")
    return record


def _safe_extract(state):
    source = state / "source" / TARBALL_NAME
    _regular(source, MAX_TARBALL_BYTES)
    target = state / "source-tree"
    if target.exists():
        if target.is_symlink():
            raise CandidateError("Candidate source tree is a symlink")
        shutil.rmtree(target)
    _ensure_directory(target)
    expected_root = f"openssh-{OPENSSH_VERSION}"
    with tarfile.open(source, "r:gz") as archive:
        members = archive.getmembers()
        if not members:
            raise CandidateError("OpenSSH archive is empty")
        for member in members:
            name = Path(member.name)
            if name.is_absolute() or ".." in name.parts:
                raise CandidateError("OpenSSH archive contains a traversal path")
            if name.parts and name.parts[0] != expected_root:
                raise CandidateError("OpenSSH archive has an unexpected top-level path")
            if member.issym() or member.islnk():
                raise CandidateError("OpenSSH archive links are refused")
            destination = (target / member.name).resolve()
            if target.resolve() not in destination.parents and destination != target.resolve():
                raise CandidateError("OpenSSH archive escapes the source directory")
        archive.extractall(target)
    root = target / expected_root
    if not root.is_dir() or (root / "configure").is_file() is False:
        raise CandidateError("OpenSSH archive did not produce a configure tree")
    return root


def _build(state):
    _load_verification(state)
    source_root = state / "source-tree" / f"openssh-{OPENSSH_VERSION}"
    if not source_root.exists():
        source_root = _safe_extract(state)
    prefix = state / "prefix"
    config_dir = state / "config"
    runtime = state / "runtime"
    for directory in (prefix, config_dir, runtime, runtime / "empty"):
        _ensure_directory(directory, 0o755 if directory.name == "empty" else 0o700)
    configure = source_root / "configure"
    _run([
        configure,
        f"--prefix={prefix}",
        f"--sysconfdir={config_dir}",
        f"--libexecdir={prefix / 'libexec'}",
        f"--with-privsep-path={runtime / 'empty'}",
        "--without-pam",
    ], cwd=source_root, timeout=300)
    jobs = str(max(1, min(os.cpu_count() or 1, 4)))
    _run(["make", "-j", jobs], cwd=source_root, timeout=900)
    _run(["make", "install"], cwd=source_root, timeout=300)
    binaries = [prefix / "sbin/sshd", prefix / "bin/ssh", prefix / "bin/ssh-keygen"]
    if not all(path.is_file() and os.access(path, os.X_OK) for path in binaries):
        raise CandidateError("Candidate build did not install the required binaries")
    _atomic_write(state / "build.json", (json.dumps({
        "owner": OWNER_MARKER, "version": OPENSSH_VERSION,
        "prefix": str(prefix), "built": True,
    }, sort_keys=True) + "\n").encode())
    return prefix


def _port(value):
    try:
        result = int(value)
    except (TypeError, ValueError) as error:
        raise CandidateError("Candidate port must be an integer") from error
    if not 1024 <= result <= 65535:
        raise CandidateError("Candidate port must be between 1024 and 65535")
    if result == 5522:
        raise CandidateError("Candidate port cannot use the managed SSH port 5522")
    return result


def _runtime_files(state, port):
    prefix = state / "prefix"
    runtime = _ensure_directory(state / "runtime")
    host_key = runtime / "host_ed25519"
    test_key = runtime / "test_ed25519"
    authorized = runtime / "authorized_keys"
    known_hosts = runtime / "known_hosts"
    config = runtime / "sshd_config"
    pid_file = runtime / "sshd.pid"
    for key in (host_key, test_key):
        if not key.exists():
            _run([prefix / "bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key], timeout=30)
        _regular(key, 8192)
        _regular(Path(str(key) + ".pub"), 8192)
    public_key = Path(str(test_key) + ".pub").read_text(encoding="ascii").strip()
    if not public_key.startswith("ssh-ed25519 "):
        raise CandidateError("Candidate test key is not an Ed25519 key")
    _atomic_write(authorized, (public_key + "\n").encode(), 0o600)
    config_text = "\n".join([
        f"Port {port}",
        "ListenAddress 127.0.0.1",
        f"HostKey {host_key}",
        f"PidFile {pid_file}",
        f"AuthorizedKeysFile {authorized}",
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
        "ChallengeResponseAuthentication no",
        "PubkeyAuthentication yes",
        "PermitRootLogin yes",
        "PermitEmptyPasswords no",
        "UsePAM no",
        "UseDNS no",
        "StrictModes yes",
        "LogLevel ERROR",
        "\n",
    ])
    _atomic_write(config, config_text.encode(), 0o600)
    return {
        "prefix": prefix, "sshd": prefix / "sbin/sshd", "ssh": prefix / "bin/ssh",
        "ssh_keyscan": prefix / "bin/ssh-keyscan", "test_key": test_key,
        "known_hosts": known_hosts, "config": config, "port": port,
    }


def _wait_for_port(process, port):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            error = (process.stderr.read() if process.stderr else "").strip()
            raise CandidateError(f"Candidate sshd exited before listening: {error[-1200:]}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise CandidateError("Candidate sshd did not listen on its isolated port")


def _stop_process(process):
    if process.poll() is not None:
        process.wait(timeout=5)
        return
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
    else:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def _candidate_test(state, port):
    files = _runtime_files(state, port)
    _run([files["sshd"], "-t", "-f", files["config"]], timeout=30)
    # `sshd -T` prints canonical mixed-case keys on OpenSSH 10.x (`Port 50222`,
    # `PasswordAuthentication no`) while older releases printed lower case. Compare
    # case-insensitively so the check means "the effective value is what we set"
    # rather than "this exact release spells keys this way" — the previous
    # lower-case-only match silently passed on 9.x and failed on a real 10.5 build.
    effective = _run([files["sshd"], "-T", "-f", files["config"]], timeout=30).stdout.lower()
    if f"port {port}\n" not in effective:
        raise CandidateError("Candidate effective configuration did not retain the isolated port")
    if "passwordauthentication no\n" not in effective or "kbdinteractiveauthentication no\n" not in effective:
        raise CandidateError("Candidate effective configuration permits password fallback")
    if not files["ssh_keyscan"].is_file():
        raise CandidateError("Candidate ssh-keyscan was not installed")
    process = subprocess.Popen(
        [files["sshd"], "-D", "-e", "-f", files["config"]],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        _wait_for_port(process, port)
        scanned = _run([
            files["ssh_keyscan"], "-T", "3", "-p", str(port), "127.0.0.1"], timeout=15).stdout
        if not scanned.strip():
            raise CandidateError("Candidate host key scan returned no key")
        _atomic_write(files["known_hosts"], scanned.encode(), 0o600)
        login = _run([
            files["ssh"], "-F", "/dev/null", "-n", "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={files['known_hosts']}",
            "-o", "GlobalKnownHostsFile=/dev/null", "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no", "-o", "IdentitiesOnly=yes",
            "-o", "ConnectTimeout=3", "-i", files["test_key"], "-p", str(port),
            "root@127.0.0.1", "printf candidate-login-ok"], timeout=30)
        if login.stdout != "candidate-login-ok":
            raise CandidateError("Candidate independent login returned unexpected output")
    finally:
        _stop_process(process)
    result = {
        "owner": OWNER_MARKER, "version": OPENSSH_VERSION, "port": port,
        "config_valid": True, "effective_config_valid": True,
        "independent_login": True, "production_switch": False,
        "production_reload": False, "production_config_changed": False,
    }
    _atomic_write(state / "test.json", (json.dumps(result, sort_keys=True) + "\n").encode())
    return result


def _switch_record_path(state):
    return state / "switch.json"


def _load_switch_record(state):
    path = _switch_record_path(state)
    if not path.exists():
        return None
    _regular(path, 8192)
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CandidateError("Invalid production switch record") from error
    if record.get("owner") != OWNER_MARKER or record.get("status") not in SWITCH_STATUSES:
        raise CandidateError("Production switch record does not belong to this owner")
    return record


def _save_switch_record(state, record):
    _atomic_write(_switch_record_path(state), (json.dumps(record, sort_keys=True) + "\n").encode())


def _effective(binary, config):
    """Security-relevant effective values as reported by `sshd -T`."""
    output = _run([str(binary), "-T", "-f", str(config)], timeout=60).stdout
    values = {}
    for line in output.splitlines():
        key, _, value = line.partition(" ")
        key = key.strip().lower()
        if key in SECURITY_KEYS:
            values.setdefault(key, []).append(value.strip())
    return {key: sorted(value) for key, value in values.items()}


def _banner(port, timeout=5):
    """Read the SSH identification string from the production listener."""
    try:
        with socket.create_connection(("127.0.0.1", int(port)), timeout=timeout) as connection:
            connection.settimeout(timeout)
            data = connection.recv(128).decode("ascii", "replace")
    except OSError:
        return None
    return data if data.startswith("SSH-2.0-") else None


def _wait_for_banner(port, timeout=20, interval=0.25):
    """Poll for the SSH banner instead of sampling once.

    SIGHUP makes sshd re-exec the on-disk binary, and during that handover the old
    process has already released the listener while the new one has not bound yet.
    A single immediate probe therefore races the re-exec and reports a false
    failure — observed on a real switch, where it caused an unnecessary rollback.
    """
    deadline = time.monotonic() + timeout
    while True:
        banner = _banner(port, timeout=2)
        if banner:
            return banner
        if time.monotonic() >= deadline:
            return None
        time.sleep(interval)


def _candidate_binary(state):
    candidate = state / "prefix/sbin/sshd"
    _regular(candidate, 64 * 1024 * 1024)
    if not os.access(candidate, os.X_OK):
        raise CandidateError("Candidate sshd is not executable")
    return candidate


def _hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _settings(args):
    return {
        "sshd": Path(args.sshd_path),
        "config": Path(args.config),
        "pidfile": Path(args.pid_file),
        "reload": args.reload_command,
        "restart": args.restart_command,
    }


def _switch_gates(state, args):
    """Everything that must hold before the production binary is replaced."""
    settings = _settings(args)
    _load_verification(state)
    test = _load_test_record(state)
    candidate = _candidate_binary(state)
    binary = settings["sshd"]
    if binary.is_symlink() or not binary.is_file():
        raise CandidateError(f"Production sshd path is not a regular file: {binary}")
    if not settings["config"].is_file():
        raise CandidateError(f"Production sshd config is missing: {settings['config']}")
    _run([str(candidate), "-t", "-f", str(settings["config"])], timeout=60)
    running = _effective(binary, settings["config"])
    planned = _effective(candidate, settings["config"])
    drift = {key: {"current": running.get(key), "candidate": planned.get(key)}
             for key in SECURITY_KEYS if running.get(key) != planned.get(key)}
    if drift and not args.accept_config_drift:
        raise CandidateError(
            "Candidate changes effective SSH policy; review and re-run with --accept-config-drift: " +
            json.dumps(drift, sort_keys=True))
    port = (running.get("port") or ["22"])[0]
    banner = _banner(port)
    if banner is None:
        raise CandidateError(f"Production sshd on port {port} is not answering; refusing to switch")
    return {"settings": settings, "candidate": candidate, "binary": binary, "port": int(port),
            "drift": drift, "banner": banner.strip(), "candidate_sha256": _hash(candidate),
            "before_sha256": _hash(binary)}


def _replace_atomically(target, payload, mode):
    target = Path(target)
    if target.is_symlink():
        raise CandidateError(f"Symlink production path refused: {target}")
    directory = target.parent
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        if os.geteuid() == 0:
            os.chown(temporary, 0, 0)
        os.replace(temporary, target)
        handle = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(handle)
        finally:
            os.close(handle)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _run_service_command(command, timeout=120):
    return subprocess.run(command, shell=True, capture_output=True, text=True, timeout=timeout)


def _restore_previous(state, record, settings):
    """Put the recorded previous binary back and make it take effect again."""
    backup = state / record["backup"]
    _regular(backup, 64 * 1024 * 1024)
    payload = backup.read_bytes()
    if hashlib.sha256(payload).hexdigest() != record["before_sha256"]:
        raise CandidateError("Recorded backup no longer matches its digest")
    _replace_atomically(settings["sshd"], payload, 0o755)
    reloaded = _run_service_command(settings["reload"])
    probe = _wait_for_banner(record["port"], SWITCH_PROBE_TIMEOUT)
    if probe is None:
        restarted = _run_service_command(settings["restart"])
        probe = _wait_for_banner(record["port"], SWITCH_PROBE_TIMEOUT)
        if probe is None:
            return {"restored": True, "reloaded": False, "restarted": restarted.returncode,
                    "detail": (restarted.stderr or restarted.stdout or "").strip()[:200]}
        return {"restored": True, "reloaded": False, "restarted": restarted.returncode}
    return {"restored": True, "reloaded": reloaded.returncode, "probe": probe.strip()}


def _watchdog(state, settings, grace):
    """Detached safety net: if the new binary does not serve, undo the switch."""
    record = _load_switch_record(state)
    if record is None or record.get("status") != "verifying":
        return 1
    time.sleep(max(1, grace))
    record = _load_switch_record(state)
    if record is None or record.get("status") != "verifying":
        return 0
    if _wait_for_banner(record["port"], SWITCH_PROBE_TIMEOUT):
        record["status"] = "verified"
        record["detail"] = "watchdog probe succeeded"
        _save_switch_record(state, record)
        return 0
    try:
        outcome = _restore_previous(state, record, settings)
        record["status"] = "auto-rolled-back"
        record["detail"] = f"production sshd did not answer after the switch: {outcome}"
    except (CandidateError, OSError, subprocess.SubprocessError) as error:
        record["status"] = "rolled-back"
        record["detail"] = f"watchdog rollback failed: {error}"
    _save_switch_record(state, record)
    return 1


def _load_test_record(state):
    path = state / "test.json"
    _regular(path, 8192)
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CandidateError("Invalid candidate test record") from error
    if (record.get("owner") != OWNER_MARKER or record.get("version") != OPENSSH_VERSION or
            record.get("independent_login") is not True or record.get("config_valid") is not True or
            record.get("effective_config_valid") is not True):
        raise CandidateError("Candidate test record does not prove an isolated login")
    return record


def _spawn_watchdog(state, settings, grace):
    """Detached safety net process; returns the Popen handle.

    Kept as its own function so tests can replace the spawn without touching
    subprocess globally (patching subprocess.Popen would also break _run).
    """
    return subprocess.Popen(
        [sys.executable, "-B", str(Path(__file__).resolve()), "watchdog",
         "--state-dir", str(state), "--sshd-path", str(settings["sshd"]),
         "--config", str(settings["config"]), "--pid-file", str(settings["pidfile"]),
         "--reload-command", settings["reload"], "--restart-command", settings["restart"],
         "--grace", str(grace)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def _switch(state, args):
    gate = _switch_gates(state, args)
    settings = gate["settings"]
    backup_dir = state / "backup"
    _ensure_directory(backup_dir)
    backup = backup_dir / (gate["before_sha256"][:16] + "-sshd")
    if not backup.exists():
        _atomic_write(backup, settings["sshd"].read_bytes(), 0o700)
    record = {
        "owner": OWNER_MARKER, "version": OPENSSH_VERSION, "status": "verifying",
        "sshd_path": str(settings["sshd"]), "config": str(settings["config"]),
        "config_sha256": _hash(settings["config"]),
        "backup": str(backup.relative_to(state)),
        "before_sha256": gate["before_sha256"], "after_sha256": gate["candidate_sha256"],
        "port": gate["port"], "drift_acknowledged": bool(gate["drift"]),
        "reload_command": settings["reload"],
    }
    if args.dry_run:
        record["status"] = "verified"
        record["detail"] = "dry run: every gate passed; nothing was replaced"
        print(json.dumps({"dry_run": True, "plan": record, "drift": gate["drift"]}, sort_keys=True))
        return record
    _replace_atomically(settings["sshd"], gate["candidate"].read_bytes(), 0o755)
    _save_switch_record(state, record)
    watchdog = _spawn_watchdog(state, settings, args.grace)
    reloaded = _run_service_command(settings["reload"])
    record["reload_rc"] = reloaded.returncode
    probe = _wait_for_banner(gate["port"], SWITCH_PROBE_TIMEOUT)
    if probe is not None:
        record["status"] = "verified"
        record["detail"] = f"new binary serving: {probe.strip()}"
        _save_switch_record(state, record)
    else:
        outcome = _restore_previous(state, record, settings)
        record["status"] = "rolled-back"
        record["detail"] = f"new binary did not answer; previous restored: {outcome}"
        _save_switch_record(state, record)
    record["watchdog_pid"] = watchdog.pid
    print(json.dumps(record, sort_keys=True))
    return record


def _rollback(state, args):
    record = _load_switch_record(state)
    if record is None:
        raise CandidateError("No production switch to roll back")
    if record["status"] == "rolled-back":
        raise CandidateError("The previous binary is already restored; nothing to roll back")
    settings = _settings(args)
    outcome = _restore_previous(state, record, settings)
    record["status"] = "rolled-back"
    record["detail"] = f"manual rollback: {outcome}"
    _save_switch_record(state, record)
    print(json.dumps(record, sort_keys=True))
    return record


def _status(state):
    verification = state / "verification.json"
    build = state / "build.json"
    test = state / "test.json"
    result = {
        "owner": OWNER_MARKER,
        "version": OPENSSH_VERSION,
        "state_dir": str(state),
        "source_downloaded": all((state / "source" / name).is_file()
                                  for name in (TARBALL_NAME, SIGNATURE_NAME, "RELEASE_KEY.asc")),
        "source_verified": verification.is_file(),
        "built": build.is_file() and (state / "prefix/sbin/sshd").is_file(),
        "tested": test.is_file(),
        "candidate_port": DEFAULT_PORT,
        "production_switch": False,
        "production_reload": False,
        "production_config_changed": False,
    }
    switch_record = _load_switch_record(state) if state.is_dir() else None
    if switch_record is not None:
        result["production_switch"] = switch_record["status"] in ("verifying", "verified")
        result["production_reload"] = switch_record["status"] in ("verifying", "verified")
        result["switch_status"] = switch_record["status"]
        result["switch_detail"] = switch_record.get("detail", "")
        result["switch_sshd_path"] = switch_record.get("sshd_path", "")
        current = Path(switch_record.get("sshd_path", ""))
        if current.is_file():
            digest = _hash(current)
            result["production_matches_candidate"] = digest == switch_record["after_sha256"]
            result["production_matches_backup"] = digest == switch_record["before_sha256"]
    if test.is_file():
        try:
            result["candidate_port"] = json.loads(test.read_text(encoding="utf-8")).get("port", DEFAULT_PORT)
        except (OSError, ValueError):
            result["tested"] = False
    print(json.dumps(result, sort_keys=True))
    return result


def _clean(state):
    marker = _marker_path(state)
    if not marker.exists():
        raise CandidateError("Candidate state owner marker is missing; refusing cleanup")
    _regular(marker, 256)
    if marker.read_text(encoding="ascii") != OWNER_MARKER + "\n":
        raise CandidateError("Candidate state owner marker mismatch")
    runtime_pid = state / "runtime/sshd.pid"
    if runtime_pid.exists():
        try:
            pid = int(runtime_pid.read_text(encoding="ascii").strip())
            os.kill(pid, 0)
        except ProcessLookupError:
            pass
        except (OSError, ValueError) as error:
            raise CandidateError(f"Refusing cleanup with an invalid active candidate PID: {error}")
        else:
            raise CandidateError("Candidate sshd appears active; stop it before cleanup")
    shutil.rmtree(state)
    print("OpenSSH candidate state removed; production sshd was not touched.")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Isolated signed OpenSSH candidate lifecycle")
    parser.add_argument("action", choices=["fetch", "verify", "build", "test", "status", "clean",
                                           "switch", "rollback", "watchdog"])
    parser.add_argument("--state-dir", default=str(DEFAULT_STATE_DIR))
    parser.add_argument("--port", default=str(DEFAULT_PORT))
    parser.add_argument("--sshd-path", default=SSHD_BINARY,
                        help="Production sshd binary (overridable for the acceptance fixture)")
    parser.add_argument("--config", default=SSHD_CONFIG, help="Production sshd configuration file")
    parser.add_argument("--pid-file", default=SSHD_PIDFILE, help="Production sshd PID file")
    parser.add_argument("--reload-command", default=SSHD_RELOAD,
                        help="Command that makes the daemon re-exec the on-disk binary")
    parser.add_argument("--restart-command", default=SSHD_RESTART,
                        help="Last-resort command used when a reload does not bring the listener back")
    parser.add_argument("--accept-config-drift", action="store_true",
                        help="Allow a candidate whose effective SSH policy differs (review the diff first)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Run every gate and print the plan without touching production")
    parser.add_argument("--grace", type=int, default=WATCHDOG_GRACE,
                        help="Seconds the detached watchdog waits before verifying or undoing a switch")
    args = parser.parse_args(argv)
    if args.action == "clean":
        state = _state_dir(args.state_dir, create=False)
    elif args.action == "watchdog":
        state = _state_dir(args.state_dir, create=False)
        try:
            return _watchdog(state, _settings(args), max(1, args.grace))
        except (CandidateError, OSError, subprocess.SubprocessError) as error:
            print(f"Watchdog refused: {error}", file=sys.stderr)
            return 1
    else:
        state = _state_dir(args.state_dir, create=args.action != "status")
    try:
        if args.action == "status":
            return 0 if _status(state) else 1
        if args.action == "clean":
            _clean(state)
            return 0
        if args.action in ("switch", "rollback"):
            if os.name != "posix" or os.geteuid() != 0:
                raise CandidateError("Switching the production sshd requires a POSIX root host")
            _claim_state(state)
            if args.action == "switch":
                _switch(state, args)
            else:
                _rollback(state, args)
            return 0
        _claim_state(state)
        if args.action == "fetch":
            _download_sources(state)
            print(f"Downloaded signed OpenSSH {OPENSSH_VERSION} sources to {state / 'source'}")
        elif args.action == "verify":
            print(json.dumps(verify_sources(state), sort_keys=True))
        elif args.action == "build":
            _build(state)
            print(f"Built OpenSSH {OPENSSH_VERSION} under {state / 'prefix'}; production sshd unchanged")
        elif args.action == "test":
            if os.name != "posix" or os.geteuid() != 0:
                raise CandidateError("Independent candidate login requires a POSIX root test host")
            _load_verification(state)
            if not (state / "prefix/sbin/sshd").is_file():
                raise CandidateError("Build the verified candidate before testing it")
            print(json.dumps(_candidate_test(state, _port(args.port)), sort_keys=True))
        return 0
    except (CandidateError, OSError, subprocess.SubprocessError, tarfile.TarError) as error:
        print(f"OpenSSH candidate refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
