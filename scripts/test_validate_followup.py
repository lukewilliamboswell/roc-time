#!/usr/bin/env python3
import copy
import sys
sys.dont_write_bytecode = True
import unittest

import validate_followup as controller


class FollowupTests(unittest.TestCase):
    def fixture(self):
        self.sha = 'a' * 40
        self.branch = 'release-followup/0.1.0-rc2'
        self.pr = {'state': 'open', 'draft': False, 'user': {'login': 'github-actions[bot]', 'type': 'Bot'},
                   'head': {'repo': {'full_name': 'owner/repo'}, 'ref': self.branch, 'sha': self.sha},
                   'base': {'repo': {'full_name': 'owner/repo'}, 'ref': 'main', 'sha': 'b' * 40},
                   'commits': 1, 'changed_files': 1}
        self.commit = {'author': {'login': 'github-actions[bot]'}, 'commit': {'verification': {'verified': True}}, 'parents': [{'sha': 'b' * 40}],
                       'files': [{'filename': 'examples/booking/main.roc', 'status': 'modified'}]}
        self.states = []
        self.dispatches = []
        self.mutation = lambda value: value

    def request(self, repository, endpoint, data=None):
        self.assertEqual(repository, 'owner/repo')
        if endpoint == 'pulls/7':
            return copy.deepcopy(self.pr)
        if endpoint.startswith('commits/'):
            return copy.deepcopy(self.commit)
        if endpoint.startswith('statuses/'):
            self.states.append(data['state'])
            return {}
        if endpoint.endswith('/dispatches'):
            self.assertEqual(data, {'ref': self.branch, 'inputs': {'nightly_validation': True}})
            self.dispatches.append(endpoint)
            return {'workflow_run_id': len(self.dispatches)}
        run_id = int(endpoint.split('/')[2])
        workflow = list(controller.WORKFLOWS)[run_id - 1]
        if '/jobs?' in endpoint:
            names = controller.WORKFLOWS[workflow]
            return self.mutation({'total_count': len(names), 'jobs': [{'name': name, 'status': 'completed', 'conclusion': 'success'} for name in names]})
        return self.mutation({'head_sha': self.sha, 'head_branch': self.branch, 'event': 'workflow_dispatch',
                              'path': '.github/workflows/' + workflow, 'status': 'completed', 'conclusion': 'success'})

    def run_candidate(self):
        return controller.validate('owner/repo', self.branch, self.sha, 7, 'main', request=self.request)

    def test_exact_head_dispatch_and_successful_required_jobs(self):
        self.fixture()
        self.assertEqual(len(self.run_candidate()), 2)
        self.assertEqual(self.states, ['pending', 'success'])
        self.assertEqual(self.dispatches, ['actions/workflows/tests.yaml/dispatches', 'actions/workflows/release.yml/dispatches'])

    def test_wrong_identity_and_workflow_edits_never_dispatch(self):
        for mutate in (lambda: self.pr['head'].update(sha='c' * 40),
                       lambda: self.pr['user'].update(login='someone'),
                       lambda: self.commit['files'][0].update(filename='.github/workflows/release.yml'),
                       lambda: self.commit['commit']['verification'].update(verified=False),
                       lambda: self.commit['files'][0].update(status='renamed'),
                       lambda: self.pr.update(changed_files=2)):
            self.fixture()
            mutate()
            with self.assertRaises(ValueError):
                self.run_candidate()
            self.assertEqual(self.dispatches, [])

    def test_failed_and_mismatched_runs_clear_pending_to_failure(self):
        for changed in ({'conclusion': 'failure'}, {'conclusion': 'skipped'}, {'head_sha': 'c' * 40},
                        {'event': 'push'}, {'path': '.github/workflows/other.yml'}):
            self.fixture()
            self.mutation = lambda value: {**value, **changed}
            with self.assertRaises(ValueError):
                self.run_candidate()
            self.assertEqual(self.states, ['pending', 'failure'])

    def test_successful_workflow_without_required_jobs_is_not_success(self):
        for jobs in ([], [{'name': 'test-examples', 'status': 'completed', 'conclusion': 'skipped'}]):
            self.fixture()
            self.mutation = lambda value: {'total_count': len(jobs), 'jobs': jobs} if 'jobs' in value else value
            with self.assertRaises(ValueError):
                self.run_candidate()
            self.assertEqual(self.states, ['pending', 'failure'])

    def test_skipped_published_examples_cannot_hide_behind_workflow_success(self):
        self.fixture()
        def mutation(value):
            for job in value.get('jobs', []):
                if job['name'] == 'Published examples with their declared compiler':
                    job['conclusion'] = 'skipped'
            return value
        self.mutation = mutation
        with self.assertRaisesRegex(ValueError, 'Published examples'):
            self.run_candidate()
        self.assertEqual(self.states, ['pending', 'failure'])

    def test_branch_or_base_movement_before_completion_is_not_success(self):
        for side in ('head', 'base'):
            self.fixture()
            def mutation(value):
                self.pr[side]['sha'] = 'c' * 40
                return value
            self.mutation = mutation
            with self.assertRaises(ValueError):
                self.run_candidate()
            self.assertEqual(self.states, ['pending', 'failure'])

    def test_incomplete_or_duplicate_file_evidence_is_not_success(self):
        self.fixture()
        self.commit['files'] *= 2
        self.pr['changed_files'] = 2
        with self.assertRaises(ValueError):
            self.run_candidate()
        self.assertEqual(self.dispatches, [])


    def test_dispatch_without_returned_id_cannot_pass(self):
        self.fixture()
        def request(repository, endpoint, data=None):
            if endpoint.endswith('/dispatches'):
                return {}
            return self.request(repository, endpoint, data)
        with self.assertRaises(ValueError):
            controller.validate('owner/repo', self.branch, self.sha, 7, 'main', request=request)
        self.assertEqual(self.states, ['pending', 'failure'])

    def test_timeout_cannot_pass(self):
        self.fixture()
        self.mutation = lambda value: {**value, 'status': 'in_progress'}
        with self.assertRaises(TimeoutError):
            controller.validate('owner/repo', self.branch, self.sha, 7, 'main', request=self.request,
                                timeout=0, monotonic=lambda: 0, sleep=lambda seconds: None)
        self.assertEqual(self.states, ['pending', 'failure'])

    def test_complete_paginated_commit_files_are_validated(self):
        self.fixture()
        self.pr['changed_files'] = 101
        self.commit['files'] = [{'filename': f'www/0.1.0/page{index}.html', 'status': 'added'} for index in range(100)]
        def request(repository, endpoint, data=None):
            if endpoint.startswith('commits/') and endpoint.endswith('page=2'):
                return {'files': [{'filename': 'www/0.1.0/index.html', 'status': 'added'}]}
            return self.request(repository, endpoint, data)
        controller.validate('owner/repo', self.branch, self.sha, 7, 'main', request=request)
        self.assertEqual(self.states, ['pending', 'success'])


if __name__ == '__main__':
    unittest.main()
