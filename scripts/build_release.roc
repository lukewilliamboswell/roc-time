#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.OsStr
import cli.Path
import src/Release
import src/Script
import src/Text

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

	Script.section!("RELEASE NOTES")?
	notes = script("scripts/release_notes.roc").exec_output!()?.stdout_utf8
	Path.write_utf8!(Path.join(output, "release-notes.md"), notes)?
	Script.info!("WROTE", Path.display(Path.join(output, "release-notes.md")))
}
