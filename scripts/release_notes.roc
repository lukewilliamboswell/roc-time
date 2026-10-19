#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Path
import cli.Stdout
import src/Release
import src/Script
import src/Text

main! = |_args| {
	# Print the release notes section for RELEASE_VERSION and the bundles named
	# by BUNDLE_DIR/roc-time-bundles.json (default dist/). The two version
	# strings replace a header pin as the record of what the release was built
	# and tested with.
	version = match Script.env_str!("RELEASE_VERSION") {
		Ok(value) if Text.valid_version(value) => value
		Ok(value) => return Script.fail!("RELEASE_VERSION is not a version: ${value}")
		Err(NotSet) => return Script.fail!("RELEASE_VERSION is required")
		Err(err) => return Err(err)
	}
	repository = Script.env_str!("REPOSITORY") ?? "lukewilliamboswell/roc-time"
	bundle_dir = Path.utf8(Script.env_str!("BUNDLE_DIR") ?? "dist")
	bundles = Release.parse_manifest(Path.read_utf8!(Path.join(bundle_dir, "roc-time-bundles.json"))?)?
	notes_file = Script.env_str!("RELEASE_NOTES_FILE") ?? "docs/releases/${version}.md"
	authored = Path.read_utf8!(Path.utf8(notes_file))?
	if Str.trim(authored).is_empty() {
		return Script.fail!("release notes are empty: ${notes_file}")
	}
	Stdout.write!("${Str.trim_end(authored)}\n\n")?
	Stdout.write!(
		Release.notes({
			version,
			repository,
			roc_version: Script.roc_nightly!()?.output!(["version"])?,
			roc_stable_version: Script.roc_stable!()?.output!(["version"])?,
			core: bundles.core,
			zones: bundles.zones,
		}),
	)
}
