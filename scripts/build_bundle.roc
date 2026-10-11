#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.OsStr
import cli.Path
import src/Files
import src/Release
import src/Script
import src/Text

main! = |_args| {
	# The bundles contain the packages being developed, so they are built with
	# the package compiler even though this script runs on roc-stable.
	# OUTPUT_DIR overrides the default dist/ directory. It receives core/ and
	# zones/, each holding one archive, and the role manifest.
	roc_nightly = Script.roc_nightly!()?
	output = Path.absolute!(Path.utf8(Script.env_str!("OUTPUT_DIR") ?? "dist"))?

	# Roc's URL identity includes the filename before the hash. Bare hashes
	# under one versioned release path would alias the two packages.
	core = bundle!(roc_nightly, "core", "package", "roc-time", output)?
	zones = bundle!(roc_nightly, "zones", "tzdb/package", "roc-time-tzdb", output)?

	manifest = Path.join(output, "roc-time-bundles.json")
	Path.write_utf8!(manifest, "${Json.to_str(Release.manifest(core, zones))}\n")?
	Script.info!("WROTE", Path.display(manifest))
}

bundle! = |roc_nightly, role, source, prefix, output| {
	directory = Path.join(output, role)
	if Path.exists!(directory)? and !Path.list!(directory)?.is_empty() {
		return Script.fail!("bundle output must be empty: ${Path.display(directory)}")
	}
	Path.create_all!(directory)?

	entries = Path.list!(source)?.map(Files.name)
	if !entries.contains("main.roc") {
		return Script.fail!("${Path.display(source)}/main.roc does not exist")
	}
	# roc bundle takes the package root first, then every other bundled file.
	modules = Text.sort_names(entries.keep_if(|name| name.ends_with(".roc") and name != "main.roc"))
	data = Text.sort_names(entries.keep_if(|name| name.ends_with(".txt") or name == "manifest.json"))
	args = ["bundle", "main.roc"]
		.concat(modules.concat(data).map(OsStr.from_str))
		.concat(["--output-dir", Path.to_os_str(directory)])
	Script.info!("+", "roc ${Str.join_with(args.map(OsStr.display), " ")}  (in ${Path.display(source)})")?
	roc_nightly.cmd(args).cwd(source).exec_cmd!()?

	match Path.list!(directory)?.keep_if(|path| Files.name(path).ends_with(".tar.zst")) {
		[built] => {
			artifact_file = "${prefix}-${Files.name(built)}"
			named = Path.join(directory, artifact_file)
			Path.rename!(built, named)?
			digest = Script.command("sha256sum").output!([Path.to_os_str(named)])?
			match Str.split_on(digest, " ") {
				[sha256, ..] => Ok({ name: role, artifact_file, sha256 })
				[] => Script.fail!("sha256sum printed nothing for ${artifact_file}")
			}
		}
		_ => Script.fail!("expected one newly built ${role} archive in ${Path.display(directory)}")
	}
}
