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
