#!/usr/bin/env python3
"""Offline failure controls for signed release follow-up creation."""
import base64
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import create_release_followup as followup


class FollowupTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1] / '.roc-time-tmp'
        root.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=root, prefix='signed-followup-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = 'a' * 40
        self.blobs = {'README.md': 'b' * 40, 'www/old.html': None}
        self.commit = {'commit': {'verification': {'verified': True}},
                       'author': {'login': 'github-actions[bot]'},
                       'parents': [{'sha': self.base}],
                       'files': [{'filename': 'README.md', 'status': 'modified', 'sha': 'b' * 40},
                                 {'filename': 'www/old.html', 'status': 'removed'}]}

    def test_exact_signed_commit_can_be_reused(self):
        followup.verify_commit(self.commit, self.base, self.blobs)

    def test_reject_unsigned_human_parent_and_unrelated_changes(self):
        for mutate in (
            lambda c: c['commit']['verification'].update(verified=False),
            lambda c: c['author'].update(login='human'),
            lambda c: c['parents'][0].update(sha='c' * 40),
            lambda c: c['parents'].append({'sha': 'c' * 40}),
            lambda c: c['files'].append({'filename': 'package/main.roc', 'status': 'added', 'sha': 'b' * 40}),
            lambda c: c['files'][0].update(sha='c' * 40),
            lambda c: c['files'][0].update(status='renamed'),
            lambda c: c['files'][1].update(status='modified'),
        ):
            commit = copy.deepcopy(self.commit)
            mutate(commit)
            with self.assertRaises(ValueError):
                followup.verify_commit(commit, self.base, self.blobs)

    def test_changes_preserve_content_deletions_and_scope(self):
        (self.root / 'README.md').write_bytes(b'hello\n')
        with patch.object(followup, 'run', side_effect=['README.md\0www/old.html\0', '']):
            changes, blobs = followup.changes(self.root, ['README.md', 'www'])
        self.assertEqual(base64.b64decode(changes['additions'][0]['contents']), b'hello\n')
        self.assertEqual(changes['deletions'], [{'path': 'www/old.html'}])
        self.assertEqual(blobs['README.md'], 'ce013625030ba8dba906f756967f9e9ca394464a')
        for path in ('package/main.roc', '../README.md', 'README.md/child'):
            with patch.object(followup, 'run', side_effect=[path + '\0', '']):
                with self.assertRaises(ValueError):
                    followup.changes(self.root, ['README.md', 'www'])

    def test_symlink_and_limits_fail(self):
        (self.root / 'README.md').symlink_to(self.root / 'target')
        with patch.object(followup, 'run', side_effect=['README.md\0', '']):
            with self.assertRaisesRegex(ValueError, 'Symlink'):
                followup.changes(self.root, ['README.md'])
        with patch.object(followup, 'MAX_FILES', 0), patch.object(followup, 'run', side_effect=['README.md\0', '']):
            with self.assertRaisesRegex(ValueError, 'file limit'):
                followup.changes(self.root, ['README.md'])

    def test_complete_paginated_commit(self):
        first = dict(self.commit, sha='d' * 40, files=[{'filename': f'www/{i}'} for i in range(100)])
        second = dict(self.commit, sha='d' * 40, files=[{'filename': 'www/last'}])
        with patch.object(followup, 'api', side_effect=[first, second]):
            self.assertEqual(len(followup.read_commit('owner/repo', 'd' * 40)['files']), 101)

    def test_graphql_errors_are_not_success(self):
        with patch.object(followup, 'run', return_value=json.dumps({'errors': [{'message': 'head moved'}]})):
            with self.assertRaisesRegex(ValueError, 'GitHub API errors'):
                followup.api('graphql', {})

    def test_outputs_reject_injection(self):
        with self.assertRaises(ValueError):
            followup.emit(self.root / 'output', {'changed': 'true\nother=value'})
        self.assertFalse((self.root / 'output').exists())


if __name__ == '__main__':
    unittest.main()
