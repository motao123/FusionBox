import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "release_downloads.py"
SPEC = importlib.util.spec_from_file_location("release_downloads", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class ReleaseDownloadsTest(unittest.TestCase):
    def test_filters_assets_and_sorts_deterministically(self):
        releases = [
            {
                "tag_name": "v2.0.0",
                "assets": [
                    {"name": "SHA256SUMS", "download_count": 99},
                    {"name": "FusionBox-v2.0.0.tar.gz", "download_count": 7},
                    {"name": "FusionBox-v2.0.0.zip", "download_count": 8},
                ],
            },
            {
                "tag_name": "v1.0.0",
                "assets": [{"name": "FusionBox-v1.0.0.tar.gz", "download_count": 3}],
            },
        ]
        metrics, shield = MODULE.build_metrics("owner/repo", releases)
        self.assertEqual(metrics["total_downloads"], 10)
        self.assertEqual(
            [item["name"] for item in metrics["assets"]],
            ["FusionBox-v1.0.0.tar.gz", "FusionBox-v2.0.0.tar.gz"],
        )
        self.assertEqual(shield["message"], "10")
        self.assertEqual(shield["schemaVersion"], 1)

    def test_follows_pagination_and_passes_token(self):
        calls = []
        pages = {
            "https://api.github.com/repos/owner/repo/releases?per_page=100&page=1": (
                [{"tag_name": "v1", "assets": []}],
                {"Link": '<https://api.github.com/next>; rel="next", <https://api.github.com/last>; rel="last"'},
            ),
            "https://api.github.com/next": ([{"tag_name": "v2", "assets": []}], {}),
        }

        def fetch(url, token):
            calls.append((url, token))
            return pages[url]

        releases = MODULE.load_releases("owner/repo", "secret", fetch)
        self.assertEqual([item["tag_name"] for item in releases], ["v1", "v2"])
        self.assertEqual(calls, [(next(iter(pages)), "secret"), ("https://api.github.com/next", "secret")])

    def test_fixture_cli_outputs_stable_json(self):
        releases = [{
            "tag_name": "v1.2.3",
            "assets": [{"name": "FusionBox-v1.2.3.tar.gz", "download_count": 42}],
        }]
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            fixture = directory / "fixture.json"
            metrics = directory / "metrics.json"
            shield = directory / "shield.json"
            fixture.write_text(json.dumps(releases), encoding="utf-8")
            subprocess.run(
                [sys.executable, str(SCRIPT), "--fixture", str(fixture), "--repository", "owner/repo",
                 "--output", str(metrics), "--shields-output", str(shield)],
                check=True,
            )
            self.assertEqual(json.loads(metrics.read_text()), {
                "assets": [{"download_count": 42, "name": "FusionBox-v1.2.3.tar.gz", "tag_name": "v1.2.3"}],
                "repository": "owner/repo",
                "total_downloads": 42,
            })
            self.assertTrue(metrics.read_bytes().endswith(b"\n"))
            self.assertEqual(json.loads(shield.read_text())["message"], "42")


if __name__ == "__main__":
    unittest.main(verbosity=2)
