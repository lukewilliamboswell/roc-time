#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Files
import src/Release
import src/Script
import src/Text

main! = |_args| {
	# Build roc-time-examples-<RELEASE_VERSION>.zip in BUNDLE_DIR (default
	# dist/) from the working tree's examples. Only the package dependency
	# lines change, to the URLs that release will give the bundles named by
	# BUNDLE_DIR/roc-time-bundles.json. REPOSITORY overrides the owner/name.
	version = match Script.env_str!("RELEASE_VERSION") {
		Ok(value) if Text.valid_version(value) => value
		Ok(value) => return Script.fail!("RELEASE_VERSION is not a version: ${value}")
		Err(NotSet) => return Script.fail!("RELEASE_VERSION is required")
		Err(err) => return Err(err)
	}
	repository = Script.env_str!("REPOSITORY") ?? "lukewilliamboswell/roc-time"
	bundle_dir = Path.absolute!(Path.utf8(Script.env_str!("BUNDLE_DIR") ?? "dist"))?
	bundles = Release.parse_manifest(Path.read_utf8!(Path.join(bundle_dir, "roc-time-bundles.json"))?)?
	core_url = Release.url(repository, version, bundles.core.artifact_file)
	zones_url = Release.url(repository, version, bundles.zones.artifact_file)

	stem = Release.archive_stem(version)
	archive = Path.join(bundle_dir, "${stem}.zip")
	if Path.exists!(archive)? {
		return Script.fail!("refusing to replace ${Path.display(archive)}")
	}
	names = Text.sort_names(Path.list!("examples")?.keep_if_try!(|path| Path.is_dir!(path))?.map(Files.name))

	Env.with_temp_dir!(
		|temporary| {
			root = Path.join(temporary, stem)
			var $files = ["${stem}/README.md"]
			Path.create_all!(Path.join(root, "expected"))?
			Path.write_utf8!(Path.join(root, "README.md"), Release.archive_readme(version, core_url, zones_url, names))?
			for name in names {
				source = Path.join("examples", name)
				destination = Path.join(Path.join(root, "examples"), name)
				Path.create_all!(destination)?
				for file in Files.direct_roc_files!(source)? {
					text = Path.read_utf8!(file)?
					rewritten = if Files.name(file) == "main.roc" Release.archive_main(text, core_url, zones_url)? else text
					Path.write_utf8!(Path.join(destination, Files.name(file)), rewritten)?
					$files = $files.append("${stem}/examples/${name}/${Files.name(file)}")
				}
				expected = Path.join("tests/examples", "${name}.txt")
				if Path.exists!(expected)? {
					Path.copy!(expected, Path.join(Path.join(root, "expected"), "${name}.txt"))?
					$files = $files.append("${stem}/expected/${name}.txt")
				}
			}
			# Entries are listed explicitly so their order does not depend on the
			# file system. Timestamps are not normalised.
			Cmd.new("zip")
				.args(["-X", "-q", Path.to_os_str(archive)].concat(Text.sort_names($files).map(OsStr.from_str)))
				.cwd(temporary)
				.exec_cmd!()
		},
	)?
	Script.info!("WROTE", "${Path.display(archive)} (${names.len().to_str()} applications)")
}
