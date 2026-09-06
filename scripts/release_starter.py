#!/usr/bin/env python3
"""Prepare or validate a starter kit bound to explicit release archive digests.

Validation reconstructs expected contents in ignored temporary storage, compares
all uncompressed members, and never replaces or extracts the supplied candidate.
No network requests, Roc builds, or publishing operations are performed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import zipfile
from urllib.parse import quote

sys.dont_write_bytecode = True
import release_bundles
import starter_kit

ROOT = Path(__file__).resolve().parents[1]
MAX_ZIP_BYTES = 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024
MAX_MEMBERS = 64


def release_urls(repo: str, version: str, role_metadata: Path, bundle_dir: Path) -> tuple[str, str]:
    if role_metadata.stat().st_size > 65536:
        raise ValueError("release role metadata exceeds 64 KiB")
    roles = release_bundles.validate_metadata(json.loads(role_metadata.read_text()))
    urls = {}
    for role, row in roles.items():
        path = bundle_dir / row["artifact_file"]
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f"missing/unsafe {role} archive")
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != row["sha256"]:
            raise ValueError(f"{role} archive digest mismatch")
        urls[role] = release_bundles.url(repo, version, row["artifact_file"])
    return urls["core"], urls["zones"]


def contents(path: Path) -> dict[str, bytes]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_ZIP_BYTES:
        raise ValueError("missing/unsafe/oversized starter ZIP")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > MAX_MEMBERS:
            raise ValueError("invalid starter ZIP member count")
        result = {}
        total = 0
        for entry in entries:
            name = entry.filename
            parts = name.split("/")
            mode = entry.external_attr >> 16
            if (name in result or not name.startswith(starter_kit.PREFIX + "/")
                    or any(part in ("", ".", "..") for part in parts)
                    or "\\" in name or any(ord(char) < 32 for char in name)
                    or entry.is_dir() or stat.S_ISLNK(mode)
                    or (stat.S_IFMT(mode) not in (0, stat.S_IFREG))
                    or entry.flag_bits & 1):
                raise ValueError(f"unsafe/duplicate starter ZIP member: {name!r}")
            total += entry.file_size
            if entry.file_size < 0 or total > MAX_UNCOMPRESSED_BYTES:
                raise ValueError("starter ZIP uncompressed size limit")
            # ZipFile verifies CRC; the size cap is checked before decompression.
            result[name] = archive.read(entry)
        return result


def prepare(repo: str, version: str, role_metadata: Path, bundle_dir: Path, kit_path: Path) -> Path:
    core, zones = release_urls(repo, version, role_metadata, bundle_dir)
    return starter_kit.build(kit_path, core, zones)


def validate(kit_path: Path, role_metadata: Path, bundle_dir: Path, repo: str, version: str) -> Path:
    core, zones = release_urls(repo, version, role_metadata, bundle_dir)
    actual = contents(kit_path)
    temporary = ROOT / ".roc-time-tmp"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-starter-", dir=temporary) as directory:
        expected_path = starter_kit.build(Path(directory) / "expected.zip", core, zones)
        expected = contents(expected_path)
    if actual.keys() != expected.keys():
        raise ValueError("starter ZIP member set differs from the release kit")
    for name, value in expected.items():
        if actual[name] != value:
            raise ValueError(f"starter ZIP content mismatch: {name}")
    return kit_path


class StarterReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = ROOT / ".roc-time-tmp"
        temporary.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="release-starter-test-", dir=temporary)
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.rows = []
        for role in ("core", "zones"):
            name = role + ".tar.zst"
            data = (role + " synthetic archive fixture").encode()
            (self.directory / name).write_bytes(data)
            self.rows.append({"name": role, "artifact_file": name, "sha256": hashlib.sha256(data).hexdigest()})
        self.metadata = self.directory / "roles.json"
        self.metadata.write_text(json.dumps({"format": "roc-time-release-bundles", "version": 1, "bundles": self.rows}))
        self.kit = self.directory / "candidate.zip"
        self.args = ("owner/repo", "1.2.3", self.metadata, self.directory, self.kit)
        prepare(*self.args)
        self.validation_args = (self.kit, self.metadata, self.directory, "owner/repo", "1.2.3")
        self.original = self.kit.read_bytes()

    def rewrite(self, transform):
        members = list(contents(self.kit).items())
        with zipfile.ZipFile(self.kit, "w") as archive:
            for name, data in transform(members):
                archive.writestr(name, data)

    def test_valid_and_no_replacement(self):
        self.assertEqual(validate(*self.validation_args), self.kit)
        self.assertEqual(self.kit.read_bytes(), self.original)

    def test_missing_extra_modified_members(self):
        changes = [lambda rows: rows[1:],
                   lambda rows: rows + [(starter_kit.PREFIX + "/extra.txt", b"extra")],
                   lambda rows: [(name, data + b"changed") if index == 0 else (name, data) for index, (name, data) in enumerate(rows)]]
        for change in changes:
            self.kit.write_bytes(self.original)
            self.rewrite(change)
            candidate = self.kit.read_bytes()
            with self.assertRaises(ValueError):
                validate(*self.validation_args)
            self.assertEqual(self.kit.read_bytes(), candidate)

    def test_wrong_compiler_source_and_url(self):
        for suffix, data in [("/.roc-version", b"wrong compiler\n"),
                             ("/examples/booking_exchange/BookingExchange.roc", b"wrong source\n"),
                             ("/examples/staffing/main.roc", b'app [main!] { zones: "https://other.invalid/wrong.tar.zst" }')]:
            self.kit.write_bytes(self.original)
            self.rewrite(lambda rows: [(name, data if name.endswith(suffix) else original) for name, original in rows])
            with self.assertRaises(ValueError):
                validate(*self.validation_args)

    def test_duplicate_and_unsafe_members(self):
        import warnings
        for name in (starter_kit.PREFIX + "/.roc-version", "../escape", starter_kit.PREFIX + "/../escape"):
            self.kit.write_bytes(self.original)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(self.kit, "a") as archive:
                    archive.writestr(name, b"bad")
            with self.assertRaises(ValueError):
                validate(*self.validation_args)
        self.kit.write_bytes(self.original)
        with zipfile.ZipFile(self.kit, "a") as archive:
            entry = zipfile.ZipInfo(starter_kit.PREFIX + "/link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, b"elsewhere")
        with self.assertRaises(ValueError):
            validate(*self.validation_args)

    def test_archive_digest_and_missing_data(self):
        (self.directory / "core.tar.zst").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "digest"):
            validate(*self.validation_args)
        (self.directory / "core.tar.zst").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            validate(*self.validation_args)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("prepare", "validate", "notes", "self-test"))
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repo")
    parser.add_argument("--version")
    parser.add_argument("--role-metadata", type=Path)
    parser.add_argument("--bundle-dir", type=Path)
    parser.add_argument("--kit-path", type=Path)
    parser.add_argument("--notes-path", type=Path)
    args = parser.parse_args()
    if args.self_test or args.command == "self-test":
        result = unittest.main(argv=[sys.argv[0]], exit=False).result
        if not result.wasSuccessful():
            raise SystemExit(1)
        return
    if not args.command or any(value is None for value in (args.repo, args.version, args.role_metadata, args.bundle_dir, args.kit_path)):
        parser.error("command and --repo/--version/--role-metadata/--bundle-dir/--kit-path are required")
    if args.command == "prepare":
        print(prepare(args.repo, args.version, args.role_metadata, args.bundle_dir, args.kit_path))
    else:
        validated = validate(args.kit_path, args.role_metadata, args.bundle_dir, args.repo, args.version)
        if args.command == "notes":
            if args.notes_path is None:
                parser.error("notes requires --notes-path")
            manifest = json.loads(contents(validated)[starter_kit.PREFIX + "/manifest.json"])
            compiler = manifest["compiler"]
            core = manifest["bundles"]["core"]
            zones = manifest["bundles"]["zones"]
            link = f"https://github.com/{args.repo}/releases/download/{quote(args.version, safe='')}/roc-time-starter.zip"
            header = (f"## Try roc-time\n\n[Download the starter kit]({link}) for booking, archive search and staffing examples. "
                      f"Use [Roc {compiler}](https://github.com/roc-lang/nightlies/releases/tag/{compiler}); "
                      "each application declares its compiler in its header. Unzip the kit, enter "
                      "`examples/booking_exchange`, and run `roc main.roc`. Python is not required.\n\n")
            header += (
                "## Packages\n\n"
                f"- [roc-time — temporal types and operations]({core})\n"
                f"- [tzdb — optional time-zone database]({zones})\n\n"
                "Copy this into `main.roc` and run `roc main.roc` with the compiler linked above:\n\n"
                "```roc\n"
                "app [main!] {\n"
                f'\troc: "{compiler}",\n'
                f'\ttime: "{core}",\n'
                f'\tzones: "{zones}",\n'
                "}\n"
                "import zones.Database\n"
                "import time.ZoneRules\n\n"
                "main! = |_args| {\n"
                '\tdata = Database.get("Australia/Melbourne")?\n'
                "\trules = ZoneRules.from_database(data)?\n"
                "\techo!(ZoneRules.name(rules))\n"
                "\tOk({})\n"
                "}\n"
                "```\n\n"
                "The tzdb dependency is optional; omit it when using only core operations.\n\n"
            )
            args.notes_path.write_text(header + args.notes_path.read_text())
        else:
            print(validated)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise SystemExit(str(error))
