"""Regression checks for public documentation version selection."""
import sys
sys.dont_write_bytecode = True

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import docs


class DocsIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (docs.ROOT / ".roc-time-tmp").mkdir(exist_ok=True)

    def setUp(self):
        temporary_root = docs.ROOT / ".roc-time-tmp"
        temporary_root.mkdir(exist_ok=True)
        self.temporary_root = temporary_root

    def test_maintenance_patch_does_not_replace_newer_stable_line(self):
        with tempfile.TemporaryDirectory(dir=self.temporary_root) as directory:
            root = Path(directory)
            for version in ("0.2.0", "0.1.2", "0.10.0", "0.9.99", "1.0.0-rc1"):
                (root / version).mkdir()
                (root / version / "index.html").write_text("generated docs")
            (root / "2.0.0").mkdir()  # An incomplete generation is not a release.
            (root / "03.0.0").mkdir()
            (root / "03.0.0" / "index.html").write_text("invalid version")
            self.assertEqual(docs.update_stable_index(root), "0.10.0")
            self.assertIn('/roc-time/0.10.0/', (root / "index.html").read_text())

    def test_prerelease_generation_preserves_root_index(self):
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

            argv = ["docs.py", "0.3.0-rc1", "--docs-root", str(output), "--source-root", str(source)]
            with patch.object(sys, "argv", argv), patch.object(docs.subprocess, "run", side_effect=generate):
                docs.main()
            self.assertEqual((output / "index.html").read_text(), "existing stable landing page")


if __name__ == "__main__":
    unittest.main()
