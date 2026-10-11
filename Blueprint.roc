# Development environment and tasks for roc-time, realised by roc-blueprint with Nix.
#
#     blueprint run check    # everything CI checks
#     blueprint run release  # build and test the bundles and examples archive
#     blueprint shell        # the environment, to run scripts/*.roc directly
#     blueprint update       # refresh Blueprint.lock
#
# Two compilers are in play and are not interchangeable. `roc-stable` is the
# release named below; it runs the scripts under scripts/. The packages and the
# examples are checked with whatever `roc` is on PATH, which is meant to be the
# latest nightly, so nothing here provides a bare `roc`.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.4.0/4jmnCGtQeuXTJJYc1rPrnA1pQFPRqUecY5oau1te8cYn.tar.zst" }

config = [
	Name("roc-time"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Overlays(["roc"]),
			Command("roc-stable", "rocpkgs.nightly-2026-10-09-258ab27"),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
				"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
			]),
			# Programs the Roc scripts start. The Python, Zig and Rust used by the
			# remaining test harness are not provided here; see CONTRIBUTING.md.
			Tools(["coreutils", "gh", "git", "unzip", "zip"]),
		],
	),
	Shell("default", [Use("dev")]),
	Task("check", [Use("dev"), Run(["roc-stable", "scripts/check_all.roc"])]),
	Task("stable-version", [Use("dev"), Run(["roc-stable", "version"])]),
	Task("release", [Use("dev"), Run(["roc-stable", "scripts/build_release.roc"])]),
	Task("latest-release", [Use("dev"), Run(["roc-stable", "scripts/latest_release.roc"])]),
	Task("site", [Use("dev"), Run(["python3", "scripts/assemble_docs_site.py", "--roc", "roc-stable"])]),
]
