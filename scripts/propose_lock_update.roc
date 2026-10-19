#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Stdout
import src/Script

branch = "automation/blueprint-lock"

lock = "Blueprint.lock"

main! = |_args| {
	# Propose the working tree's Blueprint.lock, as left by `blueprint update`, in
	# a pull request against the checked-out commit of REPOSITORY. The commit is
	# created through the GitHub API, so GitHub signs it, and it may change the
	# lock and nothing else. A pull request opened with the workflow token does
	# not start workflows, so the gate is dispatched on the branch.
	repository = Script.env_str!("REPOSITORY")?
	base = Script.env_str!("BASE_BRANCH") ?? "main"
	git = |args| Cmd.new("git").args_str(args)
	gh = |args| Cmd.new("gh").args_str(args)
	changes = Str.trim_end(git(["status", "--porcelain"]).exec_output!()?.stdout_utf8)
	if changes == "" {
		return Stdout.line!("${lock} is up to date")
	}
	if changes != " M ${lock}" {
		return Script.fail!("expected only ${lock} to change:\n${changes}")
	}
	head = Str.trim(git(["rev-parse", "HEAD"]).exec_output!()?.stdout_utf8)

	# Restart the proposal branch from the checked-out commit, keeping an open
	# pull request attached to it.
	moved = gh(["api", "--silent", "--method", "PATCH", "repos/${repository}/git/refs/heads/${branch}", "-f", "sha=${head}", "-F", "force=true"]).exec_cmd!()
	match moved {
		Ok(_) => {}
		Err(_) => gh(["api", "--silent", "repos/${repository}/git/refs", "-f", "ref=refs/heads/${branch}", "-f", "sha=${head}"]).exec_cmd!()?
	}
	contents = Str.trim(Cmd.new("base64").args_str(["--wrap=0", lock]).exec_output!()?.stdout_utf8)
	gh([
		"api",
		"graphql",
		"--silent",
		"-f",
		"query=${commit_mutation}",
		"-f",
		"repository=${repository}",
		"-f",
		"branch=${branch}",
		"-f",
		"head=${head}",
		"-f",
		"headline=${title}",
		"-f",
		"path=${lock}",
		"-f",
		"contents=${contents}",
	]).exec_cmd!()?

	open = Str.trim(gh(["pr", "list", "--repo", repository, "--head", branch, "--state", "open", "--json", "number", "--jq", "length"]).exec_output!()?.stdout_utf8)
	if open == "0" {
		gh(["pr", "create", "--repo", repository, "--base", base, "--head", branch, "--title", title, "--body", body]).exec_cmd!()?
	}
	gh(["workflow", "run", "ci.yml", "--repo", repository, "--ref", branch]).exec_cmd!()?
	Stdout.line!("Proposed ${lock} on ${branch}")
}

title = "Update Blueprint.lock"

body =
	\\`blueprint update` moved the inputs locked in `Blueprint.lock`. Nothing else changes: the tooling compiler tag and the script dependencies are named in `Blueprint.roc`.
	\\
	\\The `CI` workflow was dispatched on this branch. Pull requests opened by automation do not start pull request workflows, so close and reopen this one to run the release dry run before merging.

commit_mutation =
	\\mutation($repository: String!, $branch: String!, $head: GitObjectID!, $headline: String!, $path: String!, $contents: Base64String!) {
	\\  createCommitOnBranch(input: {
	\\    branch: { repositoryNameWithOwner: $repository, branchName: $branch },
	\\    message: { headline: $headline },
	\\    expectedHeadOid: $head,
	\\    fileChanges: { additions: [{ path: $path, contents: $contents }] }
	\\  }) { commit { oid } }
	\\}
