"""Read-only Oracle Cloud identification and legacy status inspection.

This module deliberately does not install, enable, disable, or remove anything.
It only inspects fixed, local paths and (when explicitly requested) the fixed OCI
instance metadata endpoint.  Values from either source are never included in the
CLI output.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import re
import subprocess
import sys
import urllib.error
import urllib.request

OCI_METADATA_URL = "http://169.254.169.254/opc/v2/instance/"
OCI_METADATA_TOKEN = "Oracle"
MAX_METADATA_BYTES = 16 * 1024
STATE_DIR = Path("/var/lib/fusionbox/oracle")
STATE_FILE = STATE_DIR / "state.json"
LEGACY_SCRIPT = Path("/usr/local/bin/oracle-keepalive")
LEGACY_LOG = Path("/var/log/oracle-keepalive.log")
LEGACY_CRON_MARKER = "oracle-keepalive"
DMI_PRODUCT_PATH = Path("/sys/devices/virtual/dmi/id/product_name")
DMI_VENDOR_PATH = Path("/sys/devices/virtual/dmi/id/sys_vendor")
SCHEMA_VERSION = 1

# These are deliberately small, exact allowlists.  A string merely containing
# "oracle" is not a cloud identity: Oracle Linux and many Oracle-hosted VMs use
# the same vendor/product strings without being OCI instances.
_CLOUD_ID_OCI = frozenset({"oracle", "oci", "oracle-cloud", "oracle cloud infrastructure"})
_CLOUD_PLATFORM_OCI = frozenset({"oracle", "oci", "oracle-cloud", "oracle cloud infrastructure"})
_CLOUD_INIT_NON_OCI = frozenset({
    "alibaba", "alicloud", "amazon", "aws", "azure", "cloudstack", "digitalocean",
    "ec2", "gce", "google", "ibm", "nocloud", "openstack", "scaleway",
})
_EVIDENCE = frozenset({
    "cloud-init:oci-id",
    "cloud-init:oci-platform",
    "cloud-init:non-oci",
    "dmi:oci-combination",
    "dmi:oracle-generic",
    "metadata:oci",
    "metadata:unavailable",
    "metadata:permission_denied",
    "metadata:redirect",
    "metadata:invalid",
    "metadata:oversize",
})
_ERROR_EVIDENCE = frozenset({
    "metadata:unavailable",
    "metadata:permission_denied",
    "metadata:redirect",
    "metadata:invalid",
    "metadata:oversize",
})
_OCID_RE = re.compile(r"^ocid1\.[a-z0-9-]+\.[a-z0-9-]+(?:\.[a-z0-9-]+)+$")
_REGION_RE = re.compile(r"^[a-z][a-z0-9-]{1,31}$")
_SHAPE_RE = re.compile(r"^(?:VM|BM)\.[A-Za-z0-9][A-Za-z0-9._-]{1,127}$")

_ABSENT = "absent"
_PRESENT = "present"
_PERMISSION_DENIED = "permission_denied"
_UNSAFE = "unsafe"
_UNKNOWN = "unknown"
_UNAVAILABLE = "unavailable"


def _normalise(value):
    return " ".join(value.strip().casefold().split())


def _read_text_detail(path, limit=4096):
    """Return (safe status, text) without following the final path component."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return _ABSENT, None
    except PermissionError:
        return _PERMISSION_DENIED, None
    except OSError:
        return _UNKNOWN, None
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        return _UNSAFE, None
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
        with os.fdopen(os.open(path, flags), "rb") as stream:
            current = os.fstat(stream.fileno())
            if not stat.S_ISREG(current.st_mode) or (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
                return _UNSAFE, None
            raw = stream.read(limit + 1)
        if len(raw) > limit:
            return _UNSAFE, None
        return _PRESENT, raw.decode("utf-8", errors="replace")
    except FileNotFoundError:
        return _ABSENT, None
    except PermissionError:
        return _PERMISSION_DENIED, None
    except (OSError, UnicodeError):
        return _UNKNOWN, None


def _read_text(path, limit=4096):
    status, text = _read_text_detail(path, limit)
    return text if status == _PRESENT else None


def _local_evidence():
    evidence = []
    errors = []
    product_status, product_text = _read_text_detail(DMI_PRODUCT_PATH, 512)
    vendor_status, vendor_text = _read_text_detail(DMI_VENDOR_PATH, 512)

    for item_status in (product_status, vendor_status):
        # A standard kernel/sysfs representation can be link-like on some
        # Linux builds.  It is not OCI evidence, but it is also not a read
        # permission failure.  Keep permission/I/O uncertainty visible.
        if item_status in (_PERMISSION_DENIED, _UNKNOWN):
            errors.append(f"local:{item_status}")

    product = _normalise(product_text) if product_text is not None else ""
    vendor = _normalise(vendor_text) if vendor_text is not None else ""
    # This exact pairing is the useful OCI DMI signal.  Oracle vendor alone,
    # Oracle product names, and generic KVM strings are intentionally neutral.
    if vendor == "oracle corporation" and (
        product == "kvm" or product == "kvm virtual machine" or product.startswith("kvm ")
    ):
        evidence.append("dmi:oci-combination")
    elif "oracle" in vendor or product.startswith("oracle"):
        evidence.append("dmi:oracle-generic")

    for path, marker_name, accepted in (
        (Path("/var/lib/cloud/instance/cloud-id"), "cloud-init:oci-id", _CLOUD_ID_OCI),
        (Path("/var/lib/cloud/instance/cloud-platform"), "cloud-init:oci-platform", _CLOUD_PLATFORM_OCI),
    ):
        item_status, text = _read_text_detail(path, 256)
        if item_status in (_PERMISSION_DENIED, _UNKNOWN):
            errors.append(f"local:{item_status}")
            continue
        if item_status == _UNSAFE:
            # cloud-init commonly exposes /var/lib/cloud/instance through a
            # symlink.  Do not follow it here, and do not mislabel its absence
            # as an error or as positive OCI evidence.
            continue
        if text is None:
            continue
        value = _normalise(text)
        if value in accepted:
            evidence.append(marker_name)
        elif value in _CLOUD_INIT_NON_OCI:
            evidence.append("cloud-init:non-oci")

    # Error tags are safe enum values, never paths or file content.
    evidence.extend(sorted(set(errors)))
    return evidence


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, *args, **kwargs):
        return None


def _metadata_shape_is_oci(data):
    """Validate the stable, non-secret shape of an OCI instance response."""
    if not isinstance(data, dict):
        return False
    instance_id = data.get("id")
    region = data.get("region")
    shape = data.get("shape")
    if not isinstance(instance_id, str) or not instance_id.startswith('ocid1.instance.') or not _OCID_RE.fullmatch(instance_id):
        return False
    if not isinstance(region, str) or not _REGION_RE.fullmatch(region):
        return False
    if not isinstance(shape, str) or not _SHAPE_RE.fullmatch(shape):
        return False
    # Validate other identity fields when present, but never print them.  A
    # real instance response has an OCID, region, and shape; requiring all
    # three avoids treating an arbitrary JSON object as OCI metadata.
    for key in ("compartmentId", "image"):
        value = data.get(key)
        if value is not None and (not isinstance(value, str) or not _OCID_RE.fullmatch(value)):
            return False
    for key in ("availabilityDomain", "displayName"):
        value = data.get(key)
        if value is not None and (not isinstance(value, str) or not value or len(value) > 256):
            return False
    for key in ("metadata", "freeformTags", "definedTags"):
        value = data.get(key)
        if value is not None and not isinstance(value, dict):
            return False
    return True


def _metadata_result_for_http_error(error):
    if error.code in (401, 403):
        return ["metadata:permission_denied"]
    if 300 <= error.code < 400:
        return ["metadata:redirect"]
    return ["metadata:unavailable"]


def _metadata_evidence(timeout=0.5):
    """Probe OCI IMDSv2 without proxies, redirects, credentials, or raw output."""
    request = urllib.request.Request(
        OCI_METADATA_URL,
        headers={
            "Authorization": f"Bearer {OCI_METADATA_TOKEN}",
            "Accept": "application/json",
            "Cache-Control": "no-cache",
        },
    )
    # An empty ProxyHandler is important: environment proxy variables must not
    # turn a link-local request into an externally routed request.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
    try:
        with opener.open(request, timeout=timeout) as response:
            try:
                final_url = response.geturl()
            except (AttributeError, OSError):
                return ["metadata:invalid"]
            status = getattr(response, "status", None)
            if status is None:
                status = response.getcode()
            if final_url != OCI_METADATA_URL:
                return ["metadata:redirect"]
            if status in (401, 403):
                return ["metadata:permission_denied"]
            if status != 200:
                return ["metadata:unavailable"]
            raw = response.read(MAX_METADATA_BYTES + 1)
            if len(raw) > MAX_METADATA_BYTES:
                return ["metadata:oversize"]
            data = json.loads(raw.decode("utf-8"))
            return ["metadata:oci"] if _metadata_shape_is_oci(data) else ["metadata:invalid"]
    except urllib.error.HTTPError as error:
        return _metadata_result_for_http_error(error)
    except urllib.error.URLError as error:
        if isinstance(error.reason, PermissionError):
            return ["metadata:permission_denied"]
        return ["metadata:unavailable"]
    except (OSError, TimeoutError, ValueError, TypeError, UnicodeError, json.JSONDecodeError):
        return ["metadata:unavailable"]


def _safe_evidence(items):
    return [item for item in items if item in _EVIDENCE or item.startswith("local:")]


def detect_environment(metadata=False):
    local = _safe_evidence(_local_evidence())
    remote = _safe_evidence(_metadata_evidence()) if metadata else []
    evidence = []
    for item in local + remote:
        if item not in evidence:
            evidence.append(item)

    positive = any(item in {
        "cloud-init:oci-id",
        "cloud-init:oci-platform",
        "dmi:oci-combination",
        "metadata:oci",
    } for item in evidence)
    conflict = "cloud-init:non-oci" in evidence
    verdict = "oracle" if positive and not conflict else "unknown"
    errors = sorted(
        item for item in evidence
        if item in _ERROR_EVIDENCE or item.startswith("local:")
    )
    return {
        "verdict": verdict,
        "evidence": evidence,
        "metadata_checked": bool(metadata),
        "errors": errors,
    }


def _path_status(path, reject_hardlink=False):
    """Classify a path using lstat only, including its parent directories."""
    # A symlink in a status path can redirect the inspection outside the fixed
    # location.  Check parents before the final component and never open it.
    for parent in reversed(path.parents):
        try:
            parent_info = parent.lstat()
        except FileNotFoundError:
            return _ABSENT
        except PermissionError:
            return _PERMISSION_DENIED
        except OSError:
            return _UNKNOWN
        if stat.S_ISLNK(parent_info.st_mode):
            return _UNSAFE
    try:
        info = path.lstat()
    except FileNotFoundError:
        return _ABSENT
    except PermissionError:
        return _PERMISSION_DENIED
    except OSError:
        return _UNKNOWN
    if stat.S_ISLNK(info.st_mode):
        return _UNSAFE
    if not stat.S_ISREG(info.st_mode):
        return _UNSAFE
    if reject_hardlink and info.st_nlink != 1:
        return _UNSAFE
    return _PRESENT


def _cron_status():
    try:
        cron = subprocess.run(
            ["crontab", "-l"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=3,
        )
    except FileNotFoundError:
        return _UNAVAILABLE
    except PermissionError:
        return _PERMISSION_DENIED
    except subprocess.TimeoutExpired:
        return _UNKNOWN
    except OSError:
        return _UNKNOWN
    if cron.returncode == 0:
        return _PRESENT if LEGACY_CRON_MARKER in (cron.stdout or "") else _ABSENT
    stderr = (cron.stderr or "").casefold()
    if "no crontab for" in stderr or "no crontab for user" in stderr:
        return _ABSENT
    if "permission" in stderr or "denied" in stderr or "not allowed" in stderr:
        return _PERMISSION_DENIED
    return _UNKNOWN


def _aggregate_legacy_status(values):
    if any(value == _PRESENT for value in values):
        return _PRESENT
    if any(value in {_PERMISSION_DENIED, _UNSAFE, _UNKNOWN} for value in values):
        return _UNKNOWN
    if all(value == _UNAVAILABLE for value in values):
        return _UNAVAILABLE
    return _ABSENT


def _legacy_status():
    script = _path_status(LEGACY_SCRIPT)
    log = _path_status(LEGACY_LOG)
    cron = _cron_status()
    values = (script, log, cron)
    errors = [
        f"{name}:{value}"
        for name, value in (("script", script), ("log", log), ("cron", cron))
        if value in {_PERMISSION_DENIED, _UNSAFE, _UNKNOWN}
    ]
    return {
        "script": script,
        "log": log,
        "cron": cron,
        "legacy_present": _aggregate_legacy_status(values),
        "errors": errors,
    }


def _managed_status():
    result = {
        "lifecycle": "unavailable",
        "managed": "unmanaged",
        "state_file": _ABSENT,
        "state": None,
        "error": None,
    }
    state_status = _path_status(STATE_FILE, reject_hardlink=True)
    result["state_file"] = state_status
    if state_status == _ABSENT:
        return result
    if state_status != _PRESENT:
        result["managed"] = "unknown"
        result["error"] = f"managed state is {state_status}"
        return result
    # No managed lifecycle schema is implemented.  Existence is reported, but
    # the file is never opened, parsed, or presented as validated state.
    result["error"] = "managed lifecycle unavailable; state file is not managed"
    return result


def status():
    environment = detect_environment(False)
    legacy = _legacy_status()
    managed = _managed_status()
    errors = list(environment["errors"])
    errors.extend(f"legacy:{item}" for item in legacy["errors"])
    if managed["error"] is not None and managed["managed"] == "unknown":
        errors.append(managed["error"])
    return {
        "environment": environment,
        "legacy": legacy,
        "managed": managed,
        "docker": shutil.which("docker") is not None,
        "errors": errors,
    }


def _has_errors(result):
    return bool(result.get("errors"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    detect = sub.add_parser("detect", help="conservatively identify OCI from local evidence")
    detect.add_argument("--metadata", action="store_true", help="explicitly probe fixed OCI IMDSv2")
    sub.add_parser("status", help="inspect legacy and unavailable managed lifecycle status")
    sub.add_parser("help", help="show this help")
    args = parser.parse_args(argv)
    if args.action == "help":
        parser.print_help()
        return 0
    if args.action == "detect":
        result = detect_environment(args.metadata)
    else:
        result = status()
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 1 if _has_errors(result) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, OSError) as error:
        print(f"Oracle status failed: {error}", file=sys.stderr)
        raise SystemExit(1)
