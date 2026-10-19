#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.OsStr
import cli.Cmd
import cli.Path
import src/Release
import src/Script
import src/Text
import src/Docs
import src/Manual

main! = |_args| {
	# Build and test exactly what a release publishes, into OUTPUT_DIR (default
	# dist/): both bundles, their role manifest, the examples archive for
	# RELEASE_VERSION and release-notes.md. The archive is run unchanged against
	# those exact bundles before anything is reported as built. Nothing here
	# publishes.
	version = match Script.env_str!("RELEASE_VERSION") {
		Ok(value) if Text.valid_version(value) => value
		Ok(value) => return Script.fail!("RELEASE_VERSION is not a version: ${value}")
		Err(NotSet) => return Script.fail!("RELEASE_VERSION is required")
		Err(err) => return Err(err)
	}
	output = Path.absolute!(Path.utf8(Script.env_str!("OUTPUT_DIR") ?? "dist"))?
	directory = Path.to_os_str(output)
	archive = Path.join(output, "${Release.archive_stem(version)}.zip")
	roc_stable = Script.roc_stable!()?
	script = |name| roc_stable.cmd([name]).env("RELEASE_VERSION", OsStr.from_str(version)).env("BUNDLE_DIR", directory)

	Script.section!("BUNDLES")?
	script("scripts/build_bundle.roc").env("OUTPUT_DIR", directory).exec_cmd!()?

	Script.section!("EXAMPLES ARCHIVE")?
	script("scripts/build_examples_archive.roc").exec_cmd!()?
	script("scripts/test_examples.roc").env("EXAMPLES_ARCHIVE", Path.to_os_str(archive)).exec_cmd!()?

	# Documentation is part of the tested candidate, before the immutable
	# release is published. Pages restores this exact archive afterwards.
	Script.section!("API DOCUMENTATION")?
	python = Script.env_str!("PYTHON") ?? "python3"
	docs = Path.join(output, "api-docs")
	Cmd.new_str(python)
		.args(["scripts/docs.py", OsStr.from_str(version), "--docs-root", Path.to_os_str(docs)])
		.env("ROC", Script.roc_nightly!()?.program())
		.exec_cmd!()?
	Cmd.new_str(python)
		.args(["scripts/release_docs.py", "pack", OsStr.from_str(version), "--docs-root", Path.to_os_str(docs), "--output", directory])
		.exec_cmd!()?

	Script.section!("NATIVE MANUAL")?
	manual = Path.join(output, "manual")
	Docs.build!(manual, version)?
	Manual.verify!(Path.join(manual, "site"), Bool.True)?
	pdf = Path.join(manual, "roc-time.pdf")
	if Path.read_bytes!(pdf)? != Path.read_bytes!(Path.join(Path.join(manual, "site"), "roc-time.pdf"))? {
		return Script.fail!("downloadable and site PDFs differ")
	}
	Path.copy!(pdf, Path.join(output, "roc-time-${version}.pdf"))?
	manual_archive = Path.join(output, "roc-time-manual-${version}.zip")
	Cmd.new("zip").args(["-X", "-q", "-r", Path.to_os_str(manual_archive), "."]).cwd(Path.join(manual, "site")).exec_cmd!()?
	# Exercise the archived HTML/PDF and exact API archive together, as Pages will.
	roc_stable.cmd([
		"scripts/assemble_site.roc",
		"--api-root",
		Path.to_os_str(docs),
		"--output",
		Path.to_os_str(Path.join(output, "site")),
	]).env("MANUAL_ARCHIVE", Path.to_os_str(manual_archive)).env("VERIFY_MANUAL_SOURCE", "true").exec_cmd!()?

	Script.section!("RELEASE NOTES")?
	notes = script("scripts/release_notes.roc").exec_output!()?.stdout_utf8
	Path.write_utf8!(Path.join(output, "release-notes.md"), notes)?
	Script.info!("WROTE", Path.display(Path.join(output, "release-notes.md")))
}
