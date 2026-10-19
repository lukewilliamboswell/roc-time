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
	Env.with_temp_dir!(
		|temporary| {
			archive = match Script.env_str!("MANUAL_ARCHIVE") {
				Ok(path) => Some(Path.absolute!(Path.utf8(path))?)
				Err(NotSet) => match Script.env_str!("RELEASE_VERSION") {
					Ok(version) if Text.valid_version(version) => {
						path = Path.join(temporary, "manual.zip")
						Cmd.new("gh").args([
							"release",
							"download",
							OsStr.from_str(version),
							"--repo",
							"lukewilliamboswell/roc-time",
							"--pattern",
							OsStr.from_str("roc-time-manual-${version}.zip"),
							"--output",
							Path.to_os_str(path),
						]).exec_cmd!()?
						Some(path)
					}
					Ok(_) => return Script.fail!("invalid release version")
					Err(NotSet) => None
					Err(err) => return Err(err)
				}
				Err(err) => return Err(err)
			}
			site = match archive {
				None => {
					manual = Path.join(temporary, "manual")
					Docs.build!(manual, "unreleased")?
					Path.join(manual, "site")
				}
				Some(path) => {
					listing = Script.command("unzip").output!(["-Z1", Path.to_os_str(path)])?
					for name in listing.split_on("\n").keep_if(|name| !name.is_empty()) {
						if name.starts_with("/") or name.contains("\\") or name.contains(":") or name.split_on("/").contains("..") {
							return Script.fail!("unsafe manual archive path: ${name}")
						}
					}
					metadata = Script.command("unzip").output!(["-Z", "-l", Path.to_os_str(path)])?
					if metadata.split_on("\n").any(|line| line.starts_with("l")) {
						return Script.fail!("manual archive contains a symlink")
					}
					unpacked = Path.join(temporary, "unpacked")
					Cmd.new("unzip").args(["-q", Path.to_os_str(path), "-d", Path.to_os_str(unpacked)]).exec_cmd!()?
					unpacked
				}
			}
			compare_sources = match Script.env_str!("VERIFY_MANUAL_SOURCE") {
				Ok("true") => Bool.True
				Ok("false") | Err(NotSet) => Bool.False
				Ok(_) => return Script.fail!("VERIFY_MANUAL_SOURCE must be true or false")
				Err(err) => return Err(err)
			}
			Manual.verify!(site, compare_sources)?
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
		},
	)
}
