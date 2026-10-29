# Development environment and tasks for roc-time, realised by roc-blueprint
# with released shared utilities and locked Nix native toolchains.
#
#     blueprint run check    # complete contributor gate
#     blueprint run harness  # integration cases only
#     blueprint shell        # the environment, to run scripts/*.roc directly
#     blueprint update       # refresh Blueprint.lock
#
# Two compilers are in play and are not interchangeable. `roc-stable` is the
# release named below, fetched and checked against Blueprint.lock; it runs the
# scripts under scripts/. The packages and the examples are checked with
# whatever `roc` is on PATH, which is meant to be the latest nightly, so nothing
# here provides a bare `roc`. Building, testing and publishing a release is the
# shared roc-automation workflow that .github/workflows/release.yml calls; it
# tests the exact publication artifacts separately from the contributor gate.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Recipes

config = [
	Name("roc-time"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	Packages("nix", From(NixPackages("github:NixOS/nixpkgs/31ecbaca1bdefa45dffc409f0250bd8039ea0010"))),
	# The independent generators require this exact CPython patch release.
	Packages("python", From(NixPackages("github:NixOS/nixpkgs/d3483b8587b77170fe2e2e14f35fc148cee516f8"))),
	Input("rust", "github:oxalica/rust-overlay/19ecdd08213836b36c4296a3a4f4af5a3d5308db"),
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
			# Host utilities; native compilers and PDF readers are provided below.
			Expect(["base64", "chmod", "curl", "date", "gh", "git", "sha256sum", "uname", "unzip", "tar", "zip"]),
		],
	),
	# Tasks that build or verify the manual also read its PDF.
	Environment("docs", [Extend("renderer"), Tools(["nix#poppler-utils"])]),
	Environment(
		"native",
		[
			Extend("docs"),
			Overlays(["rust"]),
			Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.6.0/release-package-{system}"))]),
			Tools(["nix#zig_0_17", "python#python314", "nix#pkg-config", "nix#gnumake", "nix#gcc"]),
			ToolWith("nix#rust-bin.stable.\"1.95.0\".default", [("targets", List([Str("x86_64-unknown-linux-musl")]))]),
		],
	),
	# The shared release workflow runs this utility against the `roc` on PATH; a
	# maintainer runs the same task locally, such as `-- test-examples --update`.
	Environment("renderer", [Extend("dev"), Programs([Fetch("roc-docs", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.6.0/roc-docs-{system}"))]), Expect(["realpath", "sh"])]),
	Environment("release", [Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.6.0/release-package-{system}"))]), Expect(["roc", "git", "gh", "tar", "unzip", "zip", "chmod", "touch", "env"])]),
	Shell("default", [Use("native")]),
	Task("check", [Use("native"), Run(["scripts/check_all.roc"])]),
	Task("check-source", [Use("dev"), Run(["scripts/check_all.roc", "--", "--source"])]),
	Task("release-package", [Use("release"), Run(["release-package"])]),
	Task("harness", [Use("native"), Run(["scripts/check_all.roc", "--", "--harness"])]),
	Task("fuzz", [Use("dev"), Run(["scripts/fuzz.roc", "--"])]),
	Task("native-versions", [Use("native"), Run(["scripts/check_native_tools.roc"])]),
	Task("measure-zone-roc", [Use("native"), Run(["scripts/measure_zone_roc.roc", "--"])]),
	Task("measure-zone-package", [Use("native"), Run(["scripts/measure_zone_package.roc", "--"])]),
	Task("measure-zone-data", [Use("dev"), Run(["scripts/measure_zone_data.roc", "--"])]),
	Task("measure-gregorian", [Use("dev"), Run(["scripts/measure_gregorian.roc", "--"])]),
	Task("fixture-platform", [Use("native"), Run(["scripts/check_fixture_platform.roc"])]),
	Task("resource-identities", [Use("native"), Run(["scripts/check_resource_identities.roc"])]),
	Task("stable-version", [Use("dev"), Run(["roc-stable", "version"])]),
	Task("check-docs", [Use("docs"), Run(["scripts/build_docs.roc"])]),
	Task("docs-path", [Use("renderer"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	Task("restore-api-docs", [Use("dev"), Run(["scripts/restore_api_docs.roc", "--"])]),
	Task("site-preview", [Use("docs"), Run(["scripts/prepare_site.roc", "--", "--preview"])]),
	Task("site-release", [Use("docs"), Run(["scripts/prepare_site.roc"])]),
	Task("docs", [Use("renderer"), Run(["roc-docs", "build", "--workspace", ".", "--output-directory", ".roc-time-tmp/docs", "--pdf-filename", "roc-time.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-time/"])]),
	Task("site", [Use("docs"), Run(["scripts/assemble_site.roc", "--"])]),
]
