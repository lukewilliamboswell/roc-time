#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Script
import src/Text

main! : List(OsStr) => Try({}, _)
main! = |args| {
	preview = match args.map(OsStr.display) {
		[] => Bool.False
		["--preview"] => Bool.True
		_ => return Script.fail!("usage: scripts/prepare_site.roc [-- --preview]")
	}
	Path.create_all!(".roc-time-tmp")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "publication-")?
	apis = Path.join(work, "api")
	Cmd.new("scripts/restore_api_docs.roc").args(["--output", Path.to_os_str(apis)]).call!()?
	version = if preview {
		"unreleased"
	} else {
		repository = Script.env_str!("GITHUB_REPOSITORY") ?? "lukewilliamboswell/roc-time"
		latest = Script.command("gh").output!(["release", "view", "--repo", OsStr.from_str(repository), "--json", "tagName,isPrerelease,isDraft"])?
		selected : { tagName : Str, isPrerelease : Bool, isDraft : Bool }
		selected = Json.parse(latest)?
		if selected.isDraft or selected.isPrerelease or !Text.is_valid_version(selected.tagName) {
			return Script.fail!("latest product release must be a final version")
		}
		selected.tagName
	}
	Cmd.new("scripts/assemble_site.roc")
		.args(["--api-root", Path.to_os_str(apis), "--output", ".roc-time-tmp/pages-site"])
		.env(OsStr.from_str("RELEASE_VERSION"), OsStr.from_str(version))
		.call!()?
	Path.delete_all!(work)
}
