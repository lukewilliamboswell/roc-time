#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Path
import cli.Stdout
import src/Release
import src/Script

main! = |_args| {
	# Describe the latest full release of REPOSITORY (prereleases are skipped):
	# its tag, the URLs of its two bundles, and the URL of its examples archive,
	# which is empty for a release published before archives existed. The
	# key=value lines are also appended to GITHUB_OUTPUT when that is set.
	repository = Script.env_str!("REPOSITORY") ?? "lukewilliamboswell/roc-time"
	gh = |args| Cmd.new("gh").args_str(args.concat(["--repo", repository]))
	summary : { tag : Str, assets : List(Str) }
	summary = Json.parse(
		gh(["release", "view", "--json", "tagName,assets", "--jq", "{tag: .tagName, assets: [.assets[].name]}"]).exec_output!()?.stdout_utf8,
	).map_err(|_| InvalidReleaseSummary)?
	if !summary.assets.contains("roc-time-bundles.json") {
		return Script.fail!("release ${summary.tag} has no roc-time-bundles.json role manifest")
	}
	manifest = gh(["release", "download", summary.tag, "--pattern", "roc-time-bundles.json", "--output", "-"]).exec_output!()?.stdout_utf8
	bundles = Release.parse_manifest(manifest)?
	archive = "${Release.archive_stem(summary.tag)}.zip"
	lines = Str.join_with(
		[
			"tag=${summary.tag}",
			"core_url=${Release.url(repository, summary.tag, bundles.core.artifact_file)}",
			"zones_url=${Release.url(repository, summary.tag, bundles.zones.artifact_file)}",
			"examples_url=${if summary.assets.contains(archive) Release.url(repository, summary.tag, archive) else ""}",
			"",
		],
		"\n",
	)
	match Script.env_str!("GITHUB_OUTPUT") {
		Ok(output) => {
			existing = if Path.exists!(Path.utf8(output))? Path.read_utf8!(Path.utf8(output))? else ""
			Path.write_utf8!(Path.utf8(output), "${existing}${lines}")?
		}
		Err(NotSet) => {}
		Err(err) => return Err(err)
	}
	Stdout.write!(lines)
}
