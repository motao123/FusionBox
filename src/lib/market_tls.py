"""Validate explicitly supplied local PEM files; never issue or copy certificates."""
import datetime
import os
from pathlib import Path
import re
import stat
import subprocess
import compose_backup as cb


def file_path(value, private=False):
    if not isinstance(value, str) or not re.fullmatch(r'/[A-Za-z0-9_./-]+', value):
        raise ValueError('TLS files require absolute safe ASCII paths')
    p = Path(value)
    if '..' in p.parts or str(p) != value:
        raise ValueError('TLS paths must be canonical')
    cb.no_links(p)
    info = p.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid():
        raise ValueError('TLS file must be a singly linked regular file owned by the operator')
    if info.st_mode & (0o177 if private else 0o022):
        raise ValueError('TLS key requires 0600/0400; certificate must not be group/world writable')
    for parent in p.parents:
        if parent.stat().st_mode & 0o022 and not parent.stat().st_mode & stat.S_ISVTX:
            raise ValueError('TLS parent directory is writable by other users')
    return value


def openssl(*args, data=None):
    result = subprocess.run(['openssl', *args], input=data, capture_output=True, timeout=15)
    if result.returncode:
        raise ValueError('TLS PEM validation failed (OpenSSL diagnostics withheld)')
    return result.stdout


def validate(domain, settings):
    if set(settings) != {'cert', 'key', 'listen', 'redirect'} or type(settings['redirect']) is not bool:
        raise ValueError('Invalid TLS settings')
    cert = file_path(settings['cert'])
    key = file_path(settings['key'], True)
    san = openssl('x509', '-in', cert, '-noout', '-ext', 'subjectAltName').decode()
    # Exact DNS SAN only: intentionally no CN fallback or wildcard matching.
    if domain not in re.findall(r'DNS:([A-Za-z0-9.-]+)(?=\s|,|$)', san):
        raise ValueError('Certificate requires an exact matching DNS SAN')
    dates = openssl('x509', '-in', cert, '-noout', '-startdate', '-enddate').decode().splitlines()
    parsed = [datetime.datetime.strptime(line.split('=', 1)[1], '%b %d %H:%M:%S %Y GMT').replace(tzinfo=datetime.timezone.utc) for line in dates]
    now = datetime.datetime.now(datetime.timezone.utc)
    if len(parsed) != 2 or not parsed[0] <= now < parsed[1]:
        raise ValueError('Certificate expired or not yet valid')
    public = openssl('x509', '-in', cert, '-pubkey', '-noout')
    public = openssl('pkey', '-pubin', '-outform', 'DER', data=public)
    actual = openssl('pkey', '-in', key, '-passin', 'pass:', '-pubout', '-outform', 'DER')
    if public != actual:
        raise ValueError('Certificate and private key do not match')
    return parsed[1].isoformat()
