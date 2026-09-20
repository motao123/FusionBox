"""Read-only Oracle Cloud identification and managed keepalive status."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

OCI_METADATA_URL = "http://169.254.169.254/opc/v2/instance/"
OCI_METADATA_TOKEN = "Oracle"
STATE_DIR = Path("/var/lib/fusionbox/oracle")
STATE_FILE = STATE_DIR / "state.json"
LEGACY_SCRIPT = Path("/usr/local/bin/oracle-keepalive")
LEGACY_LOG = Path("/var/log/oracle-keepalive.log")
LEGACY_CRON_MARKER = "oracle-keepalive"
SCHEMA_VERSION = 1


def _read_text(path, limit=4096):
    try:
        info = path.lstat()
        if not path.is_file() or info.st_size > limit:
            return None
        return path.read_text(encoding="utf-8", errors="replace")
    except (OSError, UnicodeError):
        return None


def _local_evidence():
    evidence = []
    for path in (Path("/sys/class/dmi/id/product_name"), Path("/sys/class/dmi/id/sys_vendor")):
        text = _read_text(path, 512)
        if text:
            value = text.strip().lower()
            if "oracle" in value:
                evidence.append(f"{path}:oracle")
            elif value:
                evidence.append(f"{path}:other")
    cloud = _read_text(Path("/var/lib/cloud/instance/cloud-platform"), 256)
    if cloud:
        value = cloud.strip().lower()
        if "oracle" in value or "oci" in value:
            evidence.append("/var/lib/cloud/instance/cloud-platform:oci")
        elif value:
            evidence.append("/var/lib/cloud/instance/cloud-platform:other")
    return evidence


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, *args, **kwargs):
        return None


def _metadata_evidence(timeout=0.5):
    request = urllib.request.Request(
        OCI_METADATA_URL,
        headers={"Authorization": f"Bearer {OCI_METADATA_TOKEN}", "Accept": "application/json"},
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    try:
        with opener.open(request, timeout=timeout) as response:
            if response.geturl() != OCI_METADATA_URL or response.status != 200:
                return None
            raw = response.read(16385)
            if len(raw) > 16384:
                return None
            data = json.loads(raw.decode("utf-8"))
            if not isinstance(data, dict):
                return None
            shape = data.get("shape")
            region = data.get("region")
            result = ["metadata:oci"]
            if isinstance(shape, str) and shape and len(shape) <= 128:
                result.append(f"shape:{shape}")
            if isinstance(region, str) and region and len(region) <= 128:
                result.append(f"region:{region}")
            return result
    except (OSError, ValueError, TypeError, urllib.error.URLError):
        return None


def detect_environment(metadata=False):
    local = _local_evidence()
    remote = _metadata_evidence() if metadata else None
    evidence = local + (remote or [])
    positive = any(item.endswith(":oracle") or item.endswith(":oci") for item in evidence)
    conflict = any(item.endswith(":other") for item in evidence) and not remote
    if remote and any(item == "metadata:oci" for item in remote):
        verdict = "oracle"
    elif positive and not conflict:
        verdict = "oracle"
    elif local and conflict:
        verdict = "unknown"
    else:
        verdict = "unknown"
    return {"verdict": verdict, "evidence": evidence, "metadata_checked": metadata}


def _legacy_status():
    result = {"script": False, "log": False, "cron": False}
    try:
        result["script"] = LEGACY_SCRIPT.is_file() and not LEGACY_SCRIPT.is_symlink()
        result["log"] = LEGACY_LOG.is_file() and not LEGACY_LOG.is_symlink()
    except OSError:
        pass
    try:
        cron = subprocess.run(["crontab", "-l"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True, timeout=3)
        result["cron"] = cron.returncode == 0 and any(LEGACY_CRON_MARKER in line for line in cron.stdout.splitlines())
    except (OSError, subprocess.SubprocessError):
        result["cron"] = None
    result["legacy_present"] = any(value is True for value in result.values())
    return result


def _managed_status():
    result = {"state_file": False, "state": None, "error": None}
    try:
        info = STATE_FILE.lstat()
        operator_uid = getattr(os, "geteuid", lambda: -1)()
        if not STATE_FILE.is_file() or info.st_size > 65536 or (operator_uid >= 0 and info.st_uid != operator_uid) or info.st_nlink != 1:
            result["error"] = "managed state is not a private regular file"
            return result
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
            result["error"] = "managed state schema is unsupported"
            return result
        result["state_file"] = True
        result["state"] = {
            "desired": data.get("desired"),
            "container_id": data.get("container_id"),
            "image": data.get("image"),
            "cpu_percent": data.get("cpu_percent"),
            "memory_mib": data.get("memory_mib"),
        }
    except FileNotFoundError:
        pass
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        result["error"] = "managed state cannot be read"
    return result


def status():
    return {
        "environment": detect_environment(False),
        "legacy": _legacy_status(),
        "managed": _managed_status(),
        "docker": shutil.which("docker") is not None,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    detect = sub.add_parser("detect")
    detect.add_argument("--metadata", action="store_true")
    sub.add_parser("status")
    args = parser.parse_args(argv)
    if args.action == "detect":
        print(json.dumps(detect_environment(args.metadata), ensure_ascii=False, sort_keys=True))
        return 0
    print(json.dumps(status(), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, OSError) as error:
        print(f"Oracle status failed: {error}", file=sys.stderr)
        raise SystemExit(1)
