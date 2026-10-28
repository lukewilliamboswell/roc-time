#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Docs
import src/DocLinks
import src/Files
import src/Manual
import src/Script
import src/Text

main! = |args| match args.map(OsStr.display) {
	["--api-root", api_root, "--output", output] => assemble!(Path.utf8(api_root), Path.utf8(output))
	_ => Script.fail!("usage: blueprint run site -- --api-root DIRECTORY --output NEW_DIRECTORY; received ${Str.inspect(args.map(OsStr.display))}")
}

assemble! = |api_root, destination| {
	output = Path.absolute!(destination)?
	if Path.exists!(output)? {
		return Script.fail!("site output must be new: ${Path.display(output)}")
	}
	Path.create_all!(".roc-time-tmp")?
	temporary = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "site-")?
	{
		version = Script.env_str!("RELEASE_VERSION") ?? "unreleased"
		manual = Path.join(temporary, "manual")
		if version == "unreleased" {
			Docs.build!(manual, version)?
		} else {
			if !Text.valid_version(version) {
				return Script.fail!("invalid release version")
			}
			source = Path.join(temporary, "source")
			Path.create_all!(source)?
			archive = Path.join(temporary, "source.tar")
			Cmd.new("git").args(["archive", "--format=tar", OsStr.from_str("--output=${Path.display(archive)}"), OsStr.from_str(version), "docs"]).exec_cmd!()?
			Cmd.new("tar").args(["-xf", Path.to_os_str(archive), "-C", Path.to_os_str(source)]).exec_cmd!()?
			Docs.build_from!(source, manual, version)?
		}
		site = Path.join(manual, "site")
		Manual.verify!(site, version == "unreleased")?
		Path.copy_dir!(site, output)?
		var $versions = 0.U64
		for entry in Path.list!(api_root)? {
			name = Files.name(entry)
			if Text.valid_version(name) and Path.is_dir!(entry)? {
				if !Path.exists!(Path.join(entry, "index.html"))? {
					return Script.fail!("API archive lacks ${name}/index.html")
				}
				Path.copy_dir!(entry, Path.join(output, name))?
				$versions = $versions + 1
			}
		}
		for page in Path.list!(output)?.keep_if(|path| Files.name(path).ends_with(".html")) {
			for href in DocLinks.attributes(Path.read_utf8!(page)?, "href") {
				prefix = "https://lukewilliamboswell.github.io/roc-time/"
				if href.starts_with(prefix) {
					relative = href.split_on(prefix).get(1) ?? ""
					path = relative.split_on("#").first() ?? ""
					if !Path.exists!(Path.join(output, path))? {
						return Script.fail!("manual refers to a missing published target: ${href}")
					}
				}
			}
		}
		Script.info!("PASS", "assembled native manual and ${$versions.to_str()} immutable API versions")
	}
}
