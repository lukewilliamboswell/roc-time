#!/usr/bin/env python3
"""Dispatch and verify read-only checks for the exact generated release follow-up.

Run this controller from trusted workflow source, never the candidate checkout.
"""
import argparse
import json
import os
import re
import subprocess
import time

WORKFLOWS = {"tests.yaml": ("test-examples", "Published examples with their declared compiler"),
             "release.yml": ("Build release bundle", "Test exact core and zones bundle pair")}
CONTEXT = "Release follow-up validation"


def api(repository, endpoint, data=None):
    command = ["gh", "api", f"repos/{repository}/{endpoint}",
               "-H", "X-GitHub-Api-Version: 2026-03-10"]
    if data is not None:
        command += ["--method", "POST", "--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def validate_pr(pr, repository, branch, sha, default_branch):
    if (pr.get("state") != "open" or pr.get("draft")
            or pr.get("user", {}).get("login") != "github-actions[bot]"
            or pr.get("user", {}).get("type") != "Bot"
            or pr.get("head", {}).get("repo", {}).get("full_name") != repository
            or pr.get("head", {}).get("ref") != branch or pr.get("head", {}).get("sha") != sha
            or pr.get("base", {}).get("repo", {}).get("full_name") != repository
            or pr.get("base", {}).get("ref") != default_branch
            or pr.get("commits") != 1):
        raise ValueError("Follow-up is not the expected open single-commit bot PR")


def validate_commit(commit, pr):
    files = commit.get("files", [])
    if (not commit.get("commit", {}).get("verification", {}).get("verified")
            or (commit.get("author") or {}).get("login") != "github-actions[bot]"
            or len(commit.get("parents", [])) != 1
            or commit["parents"][0].get("sha") != pr["base"]["sha"]
            or not files or len(files) != pr.get("changed_files")
            or len(files) > 3000 or len({item.get("filename") for item in files}) != len(files)):
        raise ValueError("Follow-up signature, parent, or complete file evidence is missing")
    for item in files:
        path = item.get("filename", "")
        if (item.get("status") not in {"added", "modified", "removed"}
                or any(part in {"", ".", ".."} for part in path.split("/"))
                or not (path == "README.md" or path.startswith("www/") or path.startswith("examples/"))):
            raise ValueError("Follow-up changes files beyond public docs and examples")


def validate_run(run, workflow, branch, sha):
    if (run.get("head_sha") != sha or run.get("head_branch") != branch
            or run.get("event") != "workflow_dispatch"
            or run.get("path") != f".github/workflows/{workflow}"):
        raise ValueError("Dispatched validation does not belong to the expected candidate workflow")


def validate(repository, branch, sha, number, default_branch, *, request=api, sleep=time.sleep,
             monotonic=time.monotonic, timeout=2700):
    if (not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository)
            or not re.fullmatch(r"release-followup/[A-Za-z0-9_.-]+", branch)
            or not re.fullmatch(r"[0-9a-f]{40}", sha) or number <= 0):
        raise ValueError("Invalid generated follow-up identity")

    expected_base = None

    def current():
        pr = request(repository, f"pulls/{number}")
        validate_pr(pr, repository, branch, sha, default_branch)
        if expected_base is not None and pr["base"]["sha"] != expected_base:
            raise ValueError("Follow-up base moved during validation")
        return pr

    pr = current()
    expected_base = pr["base"]["sha"]
    commit = request(repository, f"commits/{sha}?per_page=100&page=1")
    for page in range(2, 31):
        if len(commit.get("files", [])) >= pr.get("changed_files", 0):
            break
        more = request(repository, f"commits/{sha}?per_page=100&page={page}")
        if not more.get("files"):
            break
        commit["files"].extend(more["files"])
    validate_commit(commit, pr)

    def status(state, description):
        request(repository, f"statuses/{sha}", {"state": state, "context": CONTEXT,
                "description": description, "target_url": f"https://github.com/{repository}/pull/{number}"})

    status("pending", "Verifying the exact generated follow-up commit")
    runs = []
    try:
        for workflow in WORKFLOWS:
            current()
            dispatched = request(repository, f"actions/workflows/{workflow}/dispatches",
                                 {"ref": branch, "inputs": {"nightly_validation": True}})
            run_id = dispatched.get("workflow_run_id") if isinstance(dispatched, dict) else None
            if type(run_id) is not int or run_id <= 0 or any(item[1] == run_id for item in runs):
                raise ValueError("Dispatch did not return a unique validation run ID")
            runs.append((workflow, run_id))
        deadline = monotonic() + timeout
        while True:
            current()
            pending = False
            for workflow, run_id in runs:
                run = request(repository, f"actions/runs/{run_id}")
                validate_run(run, workflow, branch, sha)
                if run.get("status") != "completed":
                    pending = True
                elif run.get("conclusion") != "success":
                    raise ValueError(f"{workflow} validation did not succeed")
            if not pending:
                break
            if monotonic() >= deadline:
                raise TimeoutError("Follow-up validation timed out")
            sleep(15)
        for workflow, run_id in runs:
            jobs = request(repository, f"actions/runs/{run_id}/jobs?filter=latest&per_page=100")
            if jobs.get("total_count") != len(jobs.get("jobs", [])):
                raise ValueError("Incomplete validation job evidence")
            for name in WORKFLOWS[workflow]:
                matched = [job for job in jobs["jobs"] if job.get("name") == name]
                if (len(matched) != 1 or matched[0].get("status") != "completed"
                        or matched[0].get("conclusion") != "success"):
                    raise ValueError(f"Required validation job did not succeed: {name}")
        current()
        status("success", "Both candidate validation workflows passed")
    except Exception:
        status("failure", "Candidate validation failed, moved, or lacked evidence")
        raise
    return [f"https://github.com/{repository}/actions/runs/{run_id}" for _, run_id in runs]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--default-branch", required=True)
    args = parser.parse_args()
    links = validate(args.repo, args.branch, args.sha, args.pr, args.default_branch)
    for link in links:
        print(link)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("Validated exact release follow-up commit `" + args.sha + "`:\n\n")
            summary.writelines(f"- {link}\n" for link in links)


if __name__ == "__main__":
    main()
