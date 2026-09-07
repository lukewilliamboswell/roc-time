#!/usr/bin/env python3
"""Create one GitHub-signed bot commit for a reviewed release follow-up.

Adapted from roc-ansi scripts/create_release_followup.py and workflow_helpers.py,
revision 7241d6d97ae1e5f27ef71864a277ac7db44fa91d:
https://github.com/lukewilliamboswell/roc-ansi/tree/7241d6d97ae1e5f27ef71864a277ac7db44fa91d/scripts
Copyright © 2023 Luke Boswell and subsequent authors.
Licensed under the Universal Permissive License (UPL), Version 1.0:
https://opensource.org/license/upl
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, urlencode

sys.dont_write_bytecode = True
from docs import VERSION_RE

ALLOWED = {'www', 'examples', 'README.md'}
MAX_FILES = 3000
MAX_BYTES = 30 * 1024 * 1024


def run(args, data=None):
    return subprocess.run(args, input=data, text=True, capture_output=True,
                          check=True, timeout=120).stdout


def api(endpoint, data=None):
    args = ['gh', 'api', endpoint]
    if data is not None:
        args += ['--input', '-']
    result = json.loads(run(args, json.dumps(data) if data is not None else None))
    if isinstance(result, dict) and result.get('errors'):
        raise ValueError(f'GitHub API errors: {result["errors"]}')
    return result


def allowed(name, scopes):
    return any(name == scope or (scope != 'README.md' and name.startswith(scope + '/')) for scope in scopes)


def changes(root, scopes):
    names = set(run(['git', 'diff', '--name-only', '--no-renames', '-z', 'HEAD', '--', *scopes]).split('\0'))
    names.update(run(['git', 'ls-files', '--others', '--exclude-standard', '-z', '--', *scopes]).split('\0'))
    names.discard('')
    if len(names) > MAX_FILES:
        raise ValueError('Follow-up exceeds file limit')
    additions, deletions, blobs = [], [], {}
    size = 0
    for name in sorted(names):
        parts = Path(name).parts
        if not allowed(name, scopes) or any(part in ('', '.', '..') for part in parts) or '\\' in name:
            raise ValueError(f'Unexpected follow-up path: {name}')
        path = root / name
        if any((root.joinpath(*parts[:i])).is_symlink() for i in range(1, len(parts) + 1)):
            raise ValueError(f'Symlink follow-up path: {name}')
        if path.exists():
            if not path.is_file() or path.stat().st_mode & 0o111:
                raise ValueError(f'Non-regular or executable follow-up file: {name}')
            content = path.read_bytes()
            size += len(content)
            if size > MAX_BYTES:
                raise ValueError('Follow-up exceeds content byte limit')
            additions.append({'path': name, 'contents': base64.b64encode(content).decode()})
            blobs[name] = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        else:
            deletions.append({'path': name})
            blobs[name] = None
    return {'additions': additions, 'deletions': deletions}, blobs


def verify_commit(commit, base, blobs):
    files = commit.get('files', [])
    if (not commit.get('commit', {}).get('verification', {}).get('verified')
            or (commit.get('author') or {}).get('login') != 'github-actions[bot]'
            or [parent.get('sha') for parent in commit.get('parents', [])] != [base]
            or len(files) != len(blobs)
            or {item.get('filename') for item in files} != set(blobs)):
        raise ValueError('Follow-up is not the exact signed bot commit; refusing to overwrite branch work')
    for item in files:
        expected = blobs[item['filename']]
        if (item.get('status') not in ('added', 'modified', 'removed')
                or (expected is None and item['status'] != 'removed')
                or (expected is not None and (item['status'] == 'removed' or item.get('sha') != expected))):
            raise ValueError('Follow-up branch content differs; refusing to overwrite it')


def read_commit(repo, sha):
    combined = None
    for page in range(1, MAX_FILES // 100 + 1):
        current = api(f'repos/{repo}/commits/{sha}?per_page=100&page={page}')
        if current.get('sha') != sha or not isinstance(current.get('files'), list):
            raise ValueError('Malformed commit response')
        if combined is None:
            combined = current
        else:
            combined['files'].extend(current['files'])
        if len(current['files']) < 100:
            return combined
    raise ValueError('Commit exceeds complete file verification limit')


def emit(path, values):
    text = ''.join(f'{key}={value}\n' for key, value in values.items())
    if any('\n' in str(value) or '\r' in str(value) for value in values.values()):
        raise ValueError('GitHub outputs must be single-line')
    if path:
        with Path(path).open('a') as output:
            output.write(text)
    print(text, end='')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--version', default=os.environ.get('RELEASE_VERSION'))
    parser.add_argument('--base-branch', default=os.environ.get('DEFAULT_BRANCH'))
    parser.add_argument('--expected-base', required=True)
    parser.add_argument('--paths', nargs='+', choices=sorted(ALLOWED), default=sorted(ALLOWED))
    parser.add_argument('--github-output', default=os.environ.get('GITHUB_OUTPUT'))
    args = parser.parse_args()
    if not args.repo or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
        parser.error('Invalid repository')
    if not args.version or not VERSION_RE.fullmatch(args.version):
        parser.error('Invalid release version')
    if not args.base_branch or not re.fullmatch(r'[A-Za-z0-9_.-]+', args.base_branch):
        parser.error('Invalid base branch')
    root = Path(run(['git', 'rev-parse', '--show-toplevel']).strip()).resolve()
    base = run(['git', 'rev-parse', 'HEAD']).strip()
    if base != args.expected_base or not re.fullmatch(r'[0-9a-f]{40}', base):
        raise ValueError('Checkout differs from expected base')
    base_ref = f'repos/{args.repo}/git/ref/heads/{quote(args.base_branch, safe="")}'
    if api(base_ref)['object']['sha'] != base:
        raise ValueError('Remote base advanced; regenerate follow-up from current main')
    file_changes, blobs = changes(root, args.paths)
    branch = f'release-followup/{args.version}'
    values = {'changed': 'false', 'branch': branch, 'commit_sha': '', 'pull_request_number': ''}
    if not blobs:
        emit(args.github_output, values)
        return
    refs = api(f'repos/{args.repo}/git/matching-refs/heads/{branch}')
    refs = [ref for ref in refs if ref['ref'] == f'refs/heads/{branch}']
    if len(refs) > 1:
        raise ValueError('Ambiguous follow-up ref')
    if not refs:
        api(f'repos/{args.repo}/git/refs', {'ref': f'refs/heads/{branch}', 'sha': base})
        sha = base
    else:
        sha = refs[0]['object']['sha']
    title = f'Update docs and published examples for {args.version}'
    if sha == base:
        result = api('graphql', {'query': '''mutation($input: CreateCommitOnBranchInput!) {
          createCommitOnBranch(input: $input) { commit { oid } }
        }''', 'variables': {'input': {
            'branch': {'repositoryNameWithOwner': args.repo, 'branchName': branch},
            'expectedHeadOid': base, 'message': {'headline': title}, 'fileChanges': file_changes,
        }}})
        sha = result['data']['createCommitOnBranch']['commit']['oid']
    verify_commit(read_commit(args.repo, sha), base, blobs)
    if api(base_ref)['object']['sha'] != base:
        raise ValueError('Base advanced during follow-up creation; review generated branch')
    branch_ref = f'repos/{args.repo}/git/ref/heads/{branch}'
    if api(branch_ref)['object']['sha'] != sha:
        raise ValueError('Follow-up branch advanced during verification')
    query = urlencode({'state': 'open', 'head': f'{args.repo.split("/")[0]}:{branch}'})
    prs = api(f'repos/{args.repo}/pulls?{query}')
    body = (f'Release follow-up for {args.version}.\n\nVerified versioned documentation and published examples. '
            'Review and merge this PR to update main. This workflow does not approve or merge it.')
    if prs:
        if (len(prs) != 1 or prs[0]['base']['ref'] != args.base_branch
                or prs[0]['base']['sha'] != base or prs[0]['head']['sha'] != sha
                or prs[0]['head']['repo']['full_name'] != args.repo):
            raise ValueError('Existing release PR differs from this exact follow-up')
        pr = prs[0]
    else:
        pr = api(f'repos/{args.repo}/pulls', {'head': branch, 'base': args.base_branch, 'title': title, 'body': body})
        if pr['base']['sha'] != base or pr['head']['sha'] != sha:
            raise ValueError('PR base or head moved during creation')
    values.update(changed='true', commit_sha=sha, pull_request_number=str(pr['number']))
    emit(args.github_output, values)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        raise SystemExit(str(error))
