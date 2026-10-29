#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/ApiArchive
import src/Script
import src/Text

Asset : { name : Str, browser_download_url : Str, digest : Str, size : U64 }

Release : { tag_name : Str, draft : Bool, prerelease : Bool, assets : List(Asset) }

main! : List(OsStr) => Try({}, _)
main! = |args| match args.map(OsStr.display) {
	["--output", output] => restore_all!(Path.utf8(output))
	["--self-test"] => self_test!()
	_ => Script.fail!("usage: scripts/restore_api_docs.roc -- --output NEW_DIRECTORY")
}

restore_all! : Path => Try({}, _)
restore_all! = |output| {
	if Path.exists!(output)? {
		return Script.fail!("documentation output must be new")
	}
	Path.create_all!(output)?
	repository = Script.env_str!("GITHUB_REPOSITORY") ?? "lukewilliamboswell/roc-time"
	for page in (1.U64).to(11) {
		raw = Script.command("gh").output!(["api", OsStr.from_str("repos/${repository}/releases?per_page=100&page=${page.to_str()}")])?
		releases : List(Release)
		releases = Json.parse(raw)?
		for release in releases {
			version = release.tag_name
			if !release.draft {
				if !Text.is_valid_version(version) {
					return Script.fail!("unsupported published version ${version}")
				}
				names = ["roc-time-docs-${version}.zip", "roc-time-docs-${version}.tar.gz"]
				assets = release.assets.keep_if(|asset| names.contains(asset.name))
				asset = match assets {
					[one] => one
					_ => return Script.fail!("expected exactly one immutable API archive for ${version}")
				}
				url = "https://github.com/${repository}/releases/download/${version}/${asset.name}"
				if asset.browser_download_url != url or asset.size > 50000000 or !asset.digest.starts_with("sha256:") {
					return Script.fail!("invalid documentation asset identity for ${version}")
				}
				work = Path.join(output, ".restore-${version}")
				Path.create_all!(work)?
				archive = Path.join(work, asset.name)
				Cmd.new("curl").args([
					"--fail",
					"--silent",
					"--show-error",
					"--location",
					"--max-time",
					"60",
					OsStr.from_str(url),
					"--output",
					Path.to_os_str(archive),
				]).exec_cmd!()?
				digest = Script.command("sha256sum").output!([Path.to_os_str(archive)])?
				if !digest.starts_with("${asset.digest.drop_prefix("sha256:")} ") or Path.size_in_bytes!(archive)? != asset.size {
					return Script.fail!("documentation asset bytes differ for ${version}")
				}
				restore_archive!({
					archive,
					version,
					output,
				})?
				Path.delete_all!(work)?
				Script.info!({
					label: "RESTORED",
					message: version,
				})?
			}
		}
		if releases.len() < 100 {
			return Ok({})
		}
	}
	Script.fail!("release history exceeded 1000 entries; incomplete restoration")
}

restore_archive! : { archive : Path, version : Str, output : Path } => Try({}, _)
restore_archive! = |{ archive, version, output }| {
	if Path.exists!(Path.join(output, version))? {
		return Err(DestinationExists)
	}
	zip = Path.display(archive).ends_with(".zip")
	listing = if zip {
		Script.command("unzip").output!(["-Z1", Path.to_os_str(archive)])?
	} else {
		Script.command("tar").output!(["-tzf", Path.to_os_str(archive)])?
	}
	metadata = if zip {
		Script.command("unzip").output!(["-Z", "-l", Path.to_os_str(archive)])?
	} else {
		Script.command("tar").output!(["-tvzf", Path.to_os_str(archive)])?
	}
	ApiArchive.validate({
		version,
		entries: listing.split_on("\n"),
		metadata,
		zip,
	})?
	stage = Env.create_temp_dir_in!(output, "archive-")?
	if zip {
		Cmd.new("unzip").args(["-q", Path.to_os_str(archive), "-d", Path.to_os_str(stage)]).timeout_ms(60000).exec_cmd!()?
	} else {
		Cmd.new("tar").args([
			"-xzf",
			Path.to_os_str(archive),
			"--no-same-owner",
			"--no-same-permissions",
			"-C",
			Path.to_os_str(stage),
		]).timeout_ms(60000).exec_cmd!()?
	}
	if !Path.is_file!(Path.join(Path.join(stage, version), "index.html"))? {
		return Script.fail!("archive index must be a regular file")
	}
	Path.rename!(Path.join(stage, version), Path.join(output, version))?
	Path.delete_all!(stage)
}

self_test! : () => Try({}, _)
self_test! = || {
	Path.create_all!(".roc-time-tmp")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "archive-tests-")?
	source = Path.join(work, "source")
	Path.create_all!(Path.join(source, "0.1.0/Module"))?
	Path.write_utf8!(Path.join(source, "0.1.0/index.html"), "old exact bytes\r\n")?
	Path.write_utf8!(Path.join(source, "0.1.0/Module/index.html"), "module")?
	for zip in [Bool.False, Bool.True] {
		suffix = if (zip) "zip" else "tar.gz"
		archive = Path.join(work, "docs.${suffix}")
		if zip {
			Cmd.new("zip").args(["-q", "-r", Path.to_os_str(archive), "0.1.0"]).cwd(source).exec_cmd!()?
		} else {
			Cmd.new("tar").args(["-czf", Path.to_os_str(archive), "-C", Path.to_os_str(source), "0.1.0"]).exec_cmd!()?
		}
		output = Path.join(work, "restored-${suffix}")
		Path.create_all!(output)?
		restore_archive!({
			archive,
			version: "0.1.0",
			output,
		})?
		if Path.read_utf8!(Path.join(output, "0.1.0/index.html"))? != "old exact bytes\r\n" or Path.read_utf8!(Path.join(output, "0.1.0/Module/index.html"))? != "module" {
			return Script.fail!("archive restoration changed file bytes")
		}
		if restore_archive!({
			archive,
			version: "0.1.0",
			output,
		}).is_ok() or restore_archive!({
			archive,
			version: "0.2.0",
			output,
		}).is_ok() {
			return Script.fail!("archive overwrite/root failure control did not fail")
		}
	}
	Path.delete_all!(work)?
	Script.info!({
		label: "PASS",
		message: "ZIP and legacy tar restoration: exact bytes, overwrite and wrong-root controls",
	})
}
