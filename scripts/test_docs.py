"""Regression checks for public documentation version selection."""
import sys
sys.dont_write_bytecode = True

from pathlib import Path
import tempfile
import subprocess
import re
from html.parser import HTMLParser
import unittest
from unittest.mock import patch

import docs


class ApiInventory(HTMLParser):
    def __init__(self):
        super().__init__()
        self.entries = set()
        self.search = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "article" and "id" in attrs:
            self.entries.add(attrs["id"])
        if tag == "a" and "type-ahead-link" in attrs.get("class", "").split():
            self.search.add(attrs.get("href", "").split("#")[-1])


def require_family_methods(page, owner, methods):
    inventory = ApiInventory()
    inventory.feed(page)
    for method in methods:
        name = f"{owner}.{method}"
        if name not in inventory.entries or name not in inventory.search:
            raise AssertionError(f"Nested API method missing from documentation or search: {name}")


class DocsIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (docs.ROOT / ".roc-time-tmp").mkdir(exist_ok=True)

    def setUp(self):
        temporary_root = docs.ROOT / ".roc-time-tmp"
        temporary_root.mkdir(exist_ok=True)
        self.temporary_root = temporary_root

    def test_real_nested_api_methods_are_documented_and_searchable(self):
        # Aliases can typecheck while hiding their associated methods in docs.
        # Exercise the actual package/compiler, not invented HTML expectations.
        with tempfile.TemporaryDirectory(dir=self.temporary_root) as directory:
            output = Path(directory) / "api"
            subprocess.run([docs.roc_command(), "docs", "package/main.roc",
                            f"--output={output}"], cwd=docs.ROOT,
                           check=True, timeout=120)
            families = {
                "Calendar.Date": ("from_fields", "as_gregorian", "in_calendar", "same_day", "to_hash"),
                "Calendar.Arithmetic": ("shift_day",),
                "Calendar.Delta": ("from_components", "to_components", "days", "months"),
                "Calendar.Value": ("minute", "fractional_second", "resolution", "bounds", "to_hash"),
                "TimedSchedule.Endings": ("new", "definition", "is_eq", "to_hash"),
            }
            for owner, methods in families.items():
                page = (output / owner.split(".")[0] / "index.html").read_text()
                require_family_methods(page, owner, methods)
                # Removing either the method anchor or its search result must fail.
                method = f"{owner}.{methods[0]}"
                missing_anchor = page.replace(f'id="{method}"', 'id="removed-method"')
                with self.assertRaisesRegex(AssertionError, "Nested API method missing"):
                    require_family_methods(missing_anchor, owner, methods)
                missing_search = re.sub(r'href="[^"#]*#' + re.escape(method) + r'"', 'href="#removed-method"', page)
                with self.assertRaisesRegex(AssertionError, "Nested API method missing"):
                    require_family_methods(missing_search, owner, methods)

    def test_stable_generation_preserves_authored_root(self):
        with tempfile.TemporaryDirectory(dir=self.temporary_root) as directory:
            root = Path(directory)
            source = root / "source"
            (source / "docs").mkdir(parents=True)
            (source / "docs/overview.html").write_text("overview")
            output = root / "site"
            output.mkdir()
            (output / "index.html").write_text("existing stable landing page")

            def generate(command, **kwargs):
                version_dir = Path(command[-1].removeprefix("--output="))
                version_dir.mkdir()
                (version_dir / "index.html").write_text('<div class="main-content">')
                return type("Result", (), {"returncode": 0})()

            argv = ["docs.py", "0.3.0", "--docs-root", str(output), "--source-root", str(source)]
            with patch.object(sys, "argv", argv), patch.object(docs.subprocess, "run", side_effect=generate):
                docs.main()
            self.assertEqual((output / "index.html").read_text(), "existing stable landing page")


if __name__ == "__main__":
    unittest.main()
