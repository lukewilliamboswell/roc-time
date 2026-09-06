#!/usr/bin/env python3
"""Refuse to replace a docs site while previous release docs are absent locally."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from docs import VERSION_RE


def check_history(releases, docs_root, current):
    if not isinstance(releases, list):
        raise ValueError("Expected a release list")
    missing = []
    for release in releases:
        if not isinstance(release, dict) or type(release.get("draft")) is not bool:
            raise ValueError("Malformed release metadata")
        if release["draft"]:
            continue
        tag = release.get("tag_name")
        if not isinstance(tag, str) or not VERSION_RE.fullmatch(tag.removeprefix("v")):
            raise ValueError("Published release has an unsupported version tag")
        version = tag.removeprefix("v")
        if version != current and not (docs_root / version / "index.html").is_file():
            missing.append(tag)
    if missing:
        raise ValueError("Merge or recover earlier documentation follow-up PRs before deployment: " + ", ".join(sorted(missing)))


class HistoryTests(unittest.TestCase):
    def test_prevents_losing_an_earlier_release(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1] / ".roc-time-tmp") as tmp:
            root = Path(tmp)
            releases = [{"tag_name": "0.1.0", "draft": False}, {"tag_name": "0.2.0", "draft": False}]
            with self.assertRaisesRegex(ValueError, "0.1.0"):
                check_history(releases, root, "0.2.0")
            (root / "0.1.0").mkdir()
            (root / "0.1.0/index.html").write_text("released docs")
            check_history(releases, root, "0.2.0")

    def test_recovery_and_drafts(self):
        check_history([{"tag_name": "0.1.0-rc1", "draft": False}, {"draft": True}], Path("missing"), "0.1.0-rc1")

    def test_malformed_metadata(self):
        for rows in ({}, [{}], [{"tag_name": "../outside", "draft": False}]):
            with self.assertRaises(ValueError):
                check_history(rows, Path("missing"), "0.1.0")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo")
    parser.add_argument("--version")
    parser.add_argument("--docs-root", type=Path, default=Path("www"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        (Path(__file__).resolve().parents[1] / ".roc-time-tmp").mkdir(exist_ok=True)
        unittest.main(argv=[sys.argv[0]])
        return
    if not args.repo or not args.version or not VERSION_RE.fullmatch(args.version):
        parser.error("--repo and a SemVer --version are required")
    rows = []
    for page in range(1, 11):
        result = subprocess.run(["gh", "api", f"repos/{args.repo}/releases?per_page=100&page={page}"],
                                check=True, capture_output=True, text=True, timeout=30)
        batch = json.loads(result.stdout)
        if not isinstance(batch, list):
            raise ValueError("Expected a release list")
        rows.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise ValueError("Release history exceeds this bounded check; review before deployment")
    check_history(rows, args.docs_root, args.version)
    print("Prior release documentation is present")


if __name__ == "__main__":
    main()
