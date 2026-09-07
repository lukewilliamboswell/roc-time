#!/usr/bin/env python3
"""Compiler authority transitions must not silently select a conflicting pin."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
from roc_version import ROOT, package_requirement, read_pin, replace_pin


class CompilerAuthorityTests(unittest.TestCase):
    def test_header_and_legacy_authorities(self):
        (ROOT / '.roc-time-tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / '.roc-time-tmp') as tmp:
            root = Path(tmp)
            files = [root / 'package/main.roc', root / 'tzdb/package/main.roc']
            for path in files:
                path.parent.mkdir(parents=True)
                path.write_text('package [Example] {}\n')
            legacy = root / '.roc-version'
            with self.assertRaises(ValueError):
                package_requirement(root)
            legacy.write_text('nightly-2026-09-05-b195f5b\n')
            self.assertEqual(package_requirement(root), ('nightly-2026-09-05-b195f5b', 'legacy'))
            files[0].write_text('package [Example] { roc: "nightly-2026-09-06-d85e877" }\n')
            with self.assertRaisesRegex(ValueError, 'Mixed compiler authorities'):
                package_requirement(root)
            legacy.unlink()
            with self.assertRaisesRegex(ValueError, 'Mixed compiler authorities'):
                package_requirement(root)
            files[1].write_text(files[0].read_text())
            self.assertEqual(package_requirement(root), ('nightly-2026-09-06-d85e877', 'header'))
            files[1].write_text(replace_pin(files[1].read_text(), 'nightly-2026-09-05-b195f5b'))
            with self.assertRaisesRegex(ValueError, 'disagree'):
                package_requirement(root)

    def test_header_update_preserves_body_and_dependencies(self):
        source = 'app [main!] { roc: "nightly-2026-09-05-b195f5b", time: "https://example.org/release/hash.tar.zst" }\nmain! = |_| Ok({})\n'
        updated = replace_pin(source, 'nightly-2026-09-06-d85e877')
        self.assertEqual(updated.replace('nightly-2026-09-06-d85e877', 'nightly-2026-09-05-b195f5b'), source)
        for malformed in ('app [main!] {}', 'app [main!] { roc: "latest" }',
                          'app [main!] { roc: "0.1.0", roc: "0.2.0" }'):
            with self.assertRaises(ValueError):
                replace_pin(malformed, '0.1.0')


if __name__ == '__main__':
    unittest.main()
