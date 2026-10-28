import cli.Env
import cli.OsStr
import cli.Path
import Files
import Script

## Verified native documentation rendering. The renderer owns parsing and presentation.
Docs := [].{

	## Blueprint verifies the released executable before exposing it on PATH.
	renderer! = || Ok(Script.command("roc-docs"))

	## Build both formats inside the workspace, then copy the completed publication.
	## The destination may be a release's temporary artifact directory.
	build! = |destination, version| {
		if Path.exists!(destination)? {
			return Script.fail!("manual output must be new: ${Path.display(destination)}")
		}
		Path.create_all!(".roc-time-tmp")?
		temporary = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "manual-")?
		staged = Path.join(temporary, "rendered")
		renderer = renderer!()?
		_ = renderer.cmd([
			"build",
			"--workspace",
			Path.to_os_str(Path.absolute!(".")?),
			"--docs-directory",
			"docs",
			"--entrypoint",
			"index.adoc",
			"--output-directory",
			OsStr.from_str(".roc-time-tmp/${Files.name(temporary)}/rendered"),
			"--pdf-filename",
			"roc-time.pdf",
			"--docs-version",
			OsStr.from_str(version),
			"--author",
			"roc-time contributors",
		]).exec_cmd!()?
		Path.write_utf8!(Path.join(Path.join(staged, "site"), "THIRD_PARTY_NOTICES.txt"), renderer.output!(["--licenses"])?)?
		Path.copy_dir!(staged, destination)?
		Path.delete_all!(temporary)
	}

	## Let the native parser prepare authored AsciiDoc as Markdown for GitHub notes.
	## No downstream AsciiDoc-to-Markdown interpretation is maintained here.
	notes! = |source| {
		renderer = renderer!()?
		Env.with_temp_dir!(
			|temporary| {
				Path.create_all!(Path.join(temporary, "docs"))?
				Path.copy!(source, Path.join(Path.join(temporary, "docs"), "index.adoc"))?
				_ = renderer.cmd([
					"prepare",
					"--workspace",
					Path.to_os_str(temporary),
					"--output-directory",
					"prepared",
				]).exec_output!()?
				Path.read_utf8!(Path.join(Path.join(temporary, "prepared"), "manual.md"))
			},
		)
	}
}
