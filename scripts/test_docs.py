"""Check generated public API documentation and version selection."""
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
        self.documented = set()
        self.article_stack = []
        self.doc_depth = 0
        self.doc_owner = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "article" and "id" in attrs:
            self.entries.add(attrs["id"])
            self.article_stack.append(attrs["id"])
        if tag == "div":
            if self.doc_depth:
                self.doc_depth += 1
            elif "entry-doc" in attrs.get("class", "").split() and self.article_stack:
                self.doc_depth = 1
                self.doc_owner = self.article_stack[-1]
        if tag == "a" and "type-ahead-link" in attrs.get("class", "").split():
            self.search.add(attrs.get("href", "").split("#")[-1])

    def handle_endtag(self, tag):
        if tag == "div" and self.doc_depth:
            self.doc_depth -= 1
            if not self.doc_depth:
                self.doc_owner = None
        if tag == "article" and self.article_stack:
            self.article_stack.pop()

    def handle_data(self, data):
        if self.doc_owner is not None and data.strip():
            self.documented.add(self.doc_owner)


def require_entry_docs(page):
    inventory = ApiInventory()
    inventory.feed(page)
    missing = sorted(inventory.entries - inventory.documented)
    if missing:
        raise AssertionError("Missing public API documentation: " + ", ".join(missing))
    return len(inventory.entries)


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
            # Check actual generated entries, including nested methods. A parent's
            # description does not document its children. Presence is a gate;
            # useful caller-facing prose still needs review.
            count = sum(require_entry_docs(page.read_text())
                        for page in output.rglob("*.html"))
            self.assertGreater(count, 0, "No public API entries were generated")
            zone_output = Path(directory) / "zones"
            subprocess.run([docs.roc_command(), "docs", "tzdb/package/main.roc",
                            f"--output={zone_output}"], cwd=docs.ROOT,
                           check=True, timeout=120)
            # A package with one public module is rendered directly at its root.
            zone_page = (zone_output / "index.html").read_text()
            self.assertGreater(require_entry_docs(zone_page), 0)
            require_family_methods(zone_page, "Database", ("get",))
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

    def test_entry_docs_must_be_nonempty_and_belong_to_the_entry(self):
        parent = '<article id="Family"><div class="entry-doc"><p>Family meaning.</p></div>'
        for child in ('<article id="Family.new"></article>',
                      '<article id="Family.new"><div class="entry-doc"> </div></article>'):
            with self.assertRaisesRegex(AssertionError, r"Missing public API documentation: Family.new$"):
                require_entry_docs(parent + child + '</article>')
        page = parent + '<article id="Family.new"><div class="entry-doc"><p>Construct a value.</p></div></article></article>'
        self.assertEqual(require_entry_docs(page), 2)

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
