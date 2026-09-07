#!/usr/bin/env python3
"""Offline failure and preservation checks for immutable documentation assets."""
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import release_docs as docs

class Assets(unittest.TestCase):
    def test_deterministic_and_exact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source/0.1.0-rc1'
            source.mkdir(parents=True)
            (source / 'index.html').write_bytes(b'old exact bytes\r\n')
            a = docs.pack(source.parent, source.name, root / 'a')
            b = docs.pack(source.parent, source.name, root / 'b')
            self.assertEqual(a.read_bytes(), b.read_bytes())
            docs.restore(a, source.name, root / 'restored')
            self.assertEqual((root / 'restored/0.1.0-rc1/index.html').read_bytes(), b'old exact bytes\r\n')
            with self.assertRaisesRegex(ValueError, 'already exists'):
                docs.restore(a, source.name, root / 'restored')

    def test_unsafe_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, kind in [('0.1.0/../escape', tarfile.REGTYPE), ('0.1.0/link', tarfile.SYMTYPE)]:
                archive = root / 'bad.tar.gz'
                with tarfile.open(archive, 'w:gz') as out:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    out.addfile(entry, io.BytesIO(b''))
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    docs.restore(archive, '0.1.0', root / 'output')

    def test_missing_history_includes_prereleases(self):
        rows = [{'tag_name': '0.1.0-rc1', 'draft': False, 'prerelease': True, 'assets': []}]
        with patch.object(docs, 'github', return_value=rows):
            with self.assertRaisesRegex(ValueError, 'Missing historical'):
                docs.fetch(Path('unused'))
            docs.fetch(Path('unused'), allow_missing='0.1.0-rc1')
            with self.assertRaisesRegex(ValueError, 'Missing historical'):
                docs.fetch(Path('unused'), allow_missing='0.1.0-rc2')

    def test_existing_different_asset_is_immutable(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / docs.asset_name('0.1.0-rc1')
            archive.write_bytes(b'candidate')
            metadata = {'assets': [{'name': archive.name, 'digest': 'sha256:wrong'}]}
            with patch.object(docs, 'github', return_value=metadata), patch.object(docs.subprocess, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'refusing to replace'):
                    docs.publish(archive, '0.1.0-rc1')
                run.assert_not_called()

    def test_version_traversal(self):
        for value in ['../1.0.0', '01.0.0', '0.1.0/extra']:
            with self.assertRaises(ValueError):
                docs.version(value)

if __name__ == '__main__':
    unittest.main()
