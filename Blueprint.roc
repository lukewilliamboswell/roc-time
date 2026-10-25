# Development environment and tasks for roc-time, realised by roc-blueprint
# without Nix.
#
#     blueprint run check    # the Roc-only gate the release workflow runs first
#     blueprint run harness  # the Python, Zig and Rust harness CI runs
#     blueprint shell        # the environment, to run scripts/*.roc directly
#     blueprint update       # refresh Blueprint.lock
#
# Two compilers are in play and are not interchangeable. `roc-stable` is the
# release named below, fetched and checked against Blueprint.lock; it runs the
# scripts under scripts/. The packages and the examples are checked with
# whatever `roc` is on PATH, which is meant to be the latest nightly, so nothing
# here provides a bare `roc`. Building, testing and publishing a release is the
# shared roc-automation workflow that .github/workflows/release.yml calls; it
# runs the `check` task here before anything is packaged.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Recipes

config = [
	Name("roc-time"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	Environment(
		"dev",
		[
			Programs([Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-10-23-18478ff"))]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
				"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
			]),
			# Programs the Roc scripts start, which the machine must provide. The
			# Python, Zig and Rust used by the remaining test harness are not
			# declared here; see CONTRIBUTING.md.
			Expect(["base64", "chmod", "curl", "date", "gh", "git", "sha256sum", "uname", "unzip"]),
		],
	),
	# Tasks that build or verify the manual also read its PDF.
	Environment("docs", [Extend("dev"), Expect(["pdfinfo", "pdftotext"])]),
	# The shared release workflow runs this utility against the `roc` on PATH; a
	# maintainer runs the same task locally, such as `-- test-examples --update`.
	Environment("release", [Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.5.0/release-package-{system}"))]), Expect(["roc", "git", "gh", "tar", "unzip", "zip", "chmod", "touch", "env"])]),
	Shell("default", [Use("docs")]),
	Task("check", [Use("dev"), Run(["roc-stable", "scripts/check_all.roc"])]),
	Task("release-package", [Use("release"), Run(["release-package"])]),
	Task("harness", [Use("docs"), Run(["roc-stable", "scripts/check_all.roc", "--", "--harness"])]),
	Task("stable-version", [Use("dev"), Run(["roc-stable", "version"])]),
	Task("propose-lock-update", [Use("dev"), Run(["roc-stable", "scripts/propose_lock_update.roc"])]),
	Task("docs", [Use("docs"), Run(["roc-stable", "scripts/build_docs.roc"])]),
	Task("site", [Use("docs"), Run(["roc-stable", "scripts/assemble_site.roc", "--"])]),
]
