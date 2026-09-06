#!/usr/bin/env python3
"""Explicit core/zones release roles; never infer a role from archive count.

The pinned prepare-bundles action accepts name/path/test_os manifest rows and
emits name/artifact_file/source_path rows. Its publisher uploads archives only;
our small role manifest is an explicit additional GitHub release asset.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
ROLES = {"core", "zones"}
ASSET = "roc-time-bundles.json"
FILENAME = re.compile(r"[A-Za-z0-9_-]+\.tar\.zst\Z")


def roles(rows):
    if not isinstance(rows, list) or len(rows) != 2:
        raise ValueError("exactly core and zones bundle rows are required")
    result = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("name"), str) or row["name"] not in ROLES:
            raise ValueError("unknown or missing bundle role")
        role, name = row["name"], row.get("artifact_file", "")
        if role in result or not isinstance(name, str) or not FILENAME.fullmatch(name):
            raise ValueError("duplicate role or unsafe archive filename")
        result[role] = row
    if len({row["artifact_file"] for row in result.values()}) != 2:
        raise ValueError("core and zones must be distinct archives")
    return result


def metadata(rows, directory):
    selected = roles(rows)
    output = []
    for role in sorted(ROLES):
        name = selected[role]["artifact_file"]
        path = directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing/empty {role} archive: {path}")
        output.append({"name": role, "artifact_file": name,
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return {"format": "roc-time-release-bundles", "version": 1, "bundles": output}


def validate_metadata(value):
    if not isinstance(value, dict) or set(value) != {"format", "version", "bundles"} or value["format"] != "roc-time-release-bundles" or type(value["version"]) is not int or value["version"] != 1:
        raise ValueError("unsupported release role metadata")
    selected = roles(value["bundles"])
    for row in selected.values():
        if set(row) != {"name", "artifact_file", "sha256"} or not isinstance(row.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"]):
            raise ValueError("invalid archive digest metadata")
    return selected


def repository(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("expected owner/repository")
    return value


def url(repo, tag, filename):
    repository(repo)
    if not tag or any(ord(char) < 32 for char in tag) or not FILENAME.fullmatch(filename):
        raise ValueError("invalid release tag/archive")
    return f"https://github.com/{repo}/releases/download/{quote(tag, safe='')}/{filename}"


def previous_from_release(release, manifest, repo):
    selected = validate_metadata(manifest)
    if not isinstance(release, dict):
        raise ValueError("invalid release response")
    assets = release.get("assets")
    if not isinstance(assets, list) or any(not isinstance(asset, dict) for asset in assets):
        raise ValueError("missing release assets")
    for role, row in selected.items():
        found = [asset for asset in assets if asset.get("name") == row["artifact_file"]]
        expected_url = url(repo, release.get("tag_name", ""), row["artifact_file"])
        if len(found) != 1 or found[0].get("browser_download_url") != expected_url:
            raise ValueError(f"missing/mismatched {role} release asset")
        digest = found[0].get("digest")
        if digest is not None and digest != "sha256:" + row["sha256"]:
            raise ValueError(f"{role} release digest mismatch")
    return url(repo, release["tag_name"], selected["core"]["artifact_file"])


def gh_api(path, binary=False):
    command = ["gh", "api", path]
    if binary:
        command += ["-H", "Accept: application/octet-stream"]
    return subprocess.run(command, capture_output=True, timeout=60)


def previous(repo, provided):
    repository(repo)
    if provided:
        prefix = f"https://github.com/{repo}/releases/download/"
        if not provided.startswith(prefix) or len(provided[len(prefix):].split("/")) != 2 or not FILENAME.fullmatch(provided.rsplit("/", 1)[-1]) or any(char.isspace() for char in provided):
            raise ValueError("previous_core_url must explicitly identify this repository's release archive")
        return provided
    response = gh_api(f"repos/{repo}/releases/latest")
    if response.returncode:
        try:
            not_found = str(json.loads(response.stdout).get("status")) == "404"
        except (ValueError, AttributeError):
            not_found = False
        if not_found and gh_api(f"repos/{repo}").returncode == 0:
            return ""
        raise ValueError("cannot resolve latest release (not an accessible empty repository)")
    release = json.loads(response.stdout)
    if not isinstance(release, dict) or not isinstance(release.get("assets"), list) or any(not isinstance(asset, dict) for asset in release["assets"]):
        raise ValueError("invalid release response")
    matches = [asset for asset in release.get("assets", []) if asset.get("name") == ASSET]
    if len(matches) != 1:
        raise ValueError("latest release has no unique role metadata; supply previous_core_url explicitly for a legacy release")
    asset_id = matches[0].get("id")
    if type(asset_id) is not int or asset_id <= 0:
        raise ValueError("invalid role metadata asset id")
    response = gh_api(f"repos/{repo}/releases/assets/{asset_id}", binary=True)
    if response.returncode or len(response.stdout) > 65536:
        raise ValueError("cannot fetch bounded release role metadata")
    return previous_from_release(release, json.loads(response.stdout), repo)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def emit(values, destination):
    text = "".join(f"{key}={value}\n" for key, value in values.items())
    if destination:
        with open(destination, "a") as output:
            output.write(text)
    else:
        print(text, end="")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "metadata", "paths", "urls", "previous", "self-test"))
    parser.add_argument("--manifest", type=Path, default=Path(".release/release-bundles.json"))
    parser.add_argument("--bundle-dir", type=Path, default=Path(".release/bundles"))
    parser.add_argument("--output", type=Path, default=Path(".release") / ASSET)
    parser.add_argument("--github-output", default="")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--version", default=os.environ.get("RELEASE_VERSION", ""))
    parser.add_argument("--previous-core-url", default="")
    args = parser.parse_args()
    if args.command == "self-test":
        (ROOT / ".roc-time-tmp").mkdir(exist_ok=True)
        unittest.main(argv=[sys.argv[0]], exit=False).result.wasSuccessful() or sys.exit(1)
        return
    if args.command == "build":
        rows = []
        for role, package in (("core", "package"), ("zones", "tzdb/package")):
            directory = ROOT / "dist" / role
            if directory.exists() and list(directory.iterdir()):
                raise ValueError(f"bundle output must be empty: {directory}")
            subprocess.run([sys.executable, str(ROOT / "scripts/bundle.py"), "--package-dir", str(ROOT / package), "--output-dir", str(directory)], cwd=ROOT, check=True, timeout=180)
            paths = list(directory.glob("*.tar.zst"))
            if len(paths) != 1:
                raise ValueError(f"expected one newly built {role} archive")
            rows.append({"name": role, "path": str(paths[0].relative_to(ROOT)), "test_os": ["ubuntu-latest"]})
        write_json(args.output, rows)
    elif args.command == "previous":
        resolved = previous(args.repo, args.previous_core_url)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(resolved + "\n")
        emit({"previous_url": resolved}, args.github_output)
    else:
        rows = json.loads(args.manifest.read_text())
        if args.command == "metadata":
            write_json(args.output, metadata(rows, args.bundle_dir))
        elif args.command == "paths":
            checked = metadata(rows, args.bundle_dir)
            emit({role: str(args.bundle_dir / row["artifact_file"]) for role, row in validate_metadata(checked).items()}, args.github_output)
        else:
            emit({role + "_url": url(args.repo, args.version, row["artifact_file"]) for role, row in roles(rows).items()}, args.github_output)


class RoleTests(unittest.TestCase):
    def setUp(self):
        self.rows = [{"name": "core", "artifact_file": "a.tar.zst"}, {"name": "zones", "artifact_file": "b.tar.zst"}]

    def test_roles_reject_ambiguity(self):
        for rows in [[], self.rows[:1], self.rows * 2, [self.rows[0], {"name": "other", "artifact_file": "b.tar.zst"}], [self.rows[0], {"name": "zones", "artifact_file": "a.tar.zst"}], [{"name": "core", "artifact_file": "../a.tar.zst"}, self.rows[1]]]:
            with self.assertRaises(ValueError):
                roles(rows)

    def test_files_and_previous_binding(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".roc-time-tmp") as directory:
            path = Path(directory)
            with self.assertRaises(ValueError):
                metadata(self.rows, path)
            for name in ("a.tar.zst", "b.tar.zst"):
                (path / name).write_bytes(name.encode())
            value = metadata(self.rows, path)
            release = {"tag_name": "1.2.3", "assets": [{"name": row["artifact_file"], "browser_download_url": url("owner/repo", "1.2.3", row["artifact_file"]), "digest": "sha256:" + row["sha256"]} for row in value["bundles"]]}
            self.assertEqual(previous_from_release(release, value, "owner/repo"), "https://github.com/owner/repo/releases/download/1.2.3/a.tar.zst")
            release["assets"][0]["digest"] = "sha256:" + "0" * 64
            with self.assertRaises(ValueError):
                previous_from_release(release, value, "owner/repo")
            release["assets"] = []
            with self.assertRaises(ValueError):
                previous_from_release(release, value, "owner/repo")

    def test_legacy_requires_override(self):
        response = subprocess.CompletedProcess([], 0, json.dumps({"assets": [{"name": "a.tar.zst"}]}).encode(), b"")
        with patch(__name__ + ".gh_api", return_value=response):
            with self.assertRaisesRegex(ValueError, "previous_core_url"):
                previous("owner/repo", "")
        with patch(__name__ + ".gh_api") as request:
            supplied = "https://github.com/owner/repo/releases/download/1.2.3/a.tar.zst"
            self.assertEqual(previous("owner/repo", supplied), supplied)
            request.assert_not_called()
        with self.assertRaises(ValueError):
            previous("owner/repo", "https://github.com/other/repo/releases/download/1/a.tar.zst")

    def test_absent_release_is_not_absent_repository(self):
        absent = subprocess.CompletedProcess([], 1, b'{"status":"404"}', b"")
        visible = subprocess.CompletedProcess([], 0, b'{}', b"")
        with patch(__name__ + ".gh_api", side_effect=[absent, visible]):
            self.assertEqual(previous("owner/repo", ""), "")
        with patch(__name__ + ".gh_api", side_effect=[absent, absent]):
            with self.assertRaises(ValueError):
                previous("owner/repo", "")

    def test_metadata_version(self):
        for value in [{}, {"format": "roc-time-release-bundles", "version": True, "bundles": self.rows}]:
            with self.assertRaises(ValueError):
                validate_metadata(value)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
