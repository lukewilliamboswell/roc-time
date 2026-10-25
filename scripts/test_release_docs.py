#!/usr/bin/env python3
"""Offline failure and preservation checks for immutable documentation assets."""
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import release_docs as docs

class Assets(unittest.TestCase):
    def test_restores_zip_and_legacy_tarball_exactly(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / docs.asset_names('0.1.0-rc1')[0]
            with zipfile.ZipFile(archive, 'w') as out:
                out.writestr('0.1.0-rc1/index.html', b'old exact bytes\r\n')
                out.writestr('0.1.0-rc1/Module/index.html', b'module')
            docs.restore(archive, '0.1.0-rc1', root / 'restored')
            self.assertEqual((root / 'restored/0.1.0-rc1/index.html').read_bytes(), b'old exact bytes\r\n')
            self.assertEqual((root / 'restored/0.1.0-rc1/Module/index.html').read_bytes(), b'module')
            with self.assertRaisesRegex(ValueError, 'already exists'):
                docs.restore(archive, '0.1.0-rc1', root / 'restored')
            legacy = root / docs.asset_names('0.1.0')[1]
            with tarfile.open(legacy, 'w:gz') as out:
                entry = tarfile.TarInfo('0.1.0/index.html')
                entry.size = 5
                out.addfile(entry, io.BytesIO(b'pages'))
            docs.restore(legacy, '0.1.0', root / 'restored')
            self.assertEqual((root / 'restored/0.1.0/index.html').read_bytes(), b'pages')

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
            for name, attributes in [('0.1.0/../escape', 0), ('0.1.0/link', 0o120777 << 16), ('0.2.0/index.html', 0)]:
                archive = root / 'bad.zip'
                with zipfile.ZipFile(archive, 'w') as out:
                    info = zipfile.ZipInfo(name)
                    info.external_attr = attributes
                    out.writestr(info, b'')
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    docs.restore(archive, '0.1.0', root / 'output')
            archive = root / 'empty.zip'
            with zipfile.ZipFile(archive, 'w') as out:
                out.writestr('0.1.0/other.html', b'')
            with self.assertRaisesRegex(ValueError, 'lacks'):
                docs.restore(archive, '0.1.0', root / 'output')

    def test_missing_history_includes_prereleases(self):
        rows = [{'tag_name': '0.1.0-rc1', 'draft': False, 'prerelease': True, 'assets': []}]
        with patch.object(docs, 'github', return_value=rows):
            with self.assertRaisesRegex(ValueError, 'Missing historical'):
                docs.fetch(Path('unused'))
            docs.fetch(Path('unused'), allow_missing='0.1.0-rc1')
            with self.assertRaisesRegex(ValueError, 'Missing historical'):
                docs.fetch(Path('unused'), allow_missing='0.1.0-rc2')

    def test_both_asset_names_are_one_asset(self):
        rows = [{'tag_name': '0.1.0', 'draft': False, 'prerelease': False, 'assets': [
            {'name': 'roc-time-docs-0.1.0.zip'}, {'name': 'roc-time-docs-0.1.0.tar.gz'}]}]
        with patch.object(docs, 'github', return_value=rows):
            with self.assertRaisesRegex(ValueError, 'Multiple'):
                docs.fetch(Path('unused'))

    def test_version_traversal(self):
        for value in ['../1.0.0', '01.0.0', '0.1.0/extra']:
            with self.assertRaises(ValueError):
                docs.version(value)

if __name__ == '__main__':
    unittest.main()
