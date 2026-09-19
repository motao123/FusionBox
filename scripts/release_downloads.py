#!/usr/bin/env python3
"""Collect FusionBox GitHub Release archive download counts."""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable, Iterable

API_VERSION = "2022-11-28"
ASSET_PATTERN = re.compile(r"^FusionBox-v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz$")
DEFAULT_REPOSITORY = "motao123/FusionBox"


def request_json(url: str, token: str | None = None) -> tuple[object, dict[str, str]]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "FusionBox-release-metrics",
        "X-GitHub-Api-Version": API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response), dict(response.headers.items())


def next_link(link_header: str | None) -> str | None:
    if not link_header:
        return None
    for item in link_header.split(","):
        parts = [part.strip() for part in item.split(";")]
        if len(parts) > 1 and 'rel="next"' in parts[1:]:
            return parts[0].strip("<>")
    return None


def load_releases(
    repository: str,
    token: str | None,
    fetch: Callable[[str, str | None], tuple[object, dict[str, str]]] = request_json,
) -> list[dict]:
    url = f"https://api.github.com/repos/{repository}/releases?per_page=100&page=1"
    releases: list[dict] = []
    while url:
        payload, headers = fetch(url, token)
        if not isinstance(payload, list):
            raise ValueError("GitHub Releases API returned a non-list payload")
        releases.extend(item for item in payload if isinstance(item, dict))
        url = next_link(headers.get("Link") or headers.get("link"))
    return releases


def build_metrics(repository: str, releases: Iterable[dict]) -> tuple[dict, dict]:
    assets = []
    for release in releases:
        tag = str(release.get("tag_name", ""))
        for asset in release.get("assets", []):
            if not isinstance(asset, dict):
                continue
            name = str(asset.get("name", ""))
            if not ASSET_PATTERN.fullmatch(name):
                continue
            assets.append(
                {
                    "download_count": int(asset.get("download_count", 0)),
                    "name": name,
                    "tag_name": tag,
                }
            )
    assets.sort(key=lambda item: (item["tag_name"], item["name"]))
    total = sum(item["download_count"] for item in assets)
    metrics = {
        "assets": assets,
        "repository": repository,
        "total_downloads": total,
    }
    shield = {
        "schemaVersion": 1,
        "label": "release downloads",
        "message": str(total),
        "color": "blue",
    }
    return metrics, shield


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    parser.add_argument("--fixture", type=Path, help="Read a release list from a deterministic local fixture")
    parser.add_argument("--output", type=Path, default=Path("docs/generated/github-metrics.json"))
    parser.add_argument("--shields-output", type=Path, default=Path("docs/generated/github-downloads-shield.json"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.fixture:
            releases = json.loads(args.fixture.read_text(encoding="utf-8"))
            if not isinstance(releases, list):
                raise ValueError("fixture must contain a JSON release list")
        else:
            releases = load_releases(args.repository, args.token)
        metrics, shield = build_metrics(args.repository, releases)
        write_json(args.output, metrics)
        write_json(args.shields_output, shield)
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError) as error:
        raise SystemExit(f"release metrics failed: {error}") from error
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
