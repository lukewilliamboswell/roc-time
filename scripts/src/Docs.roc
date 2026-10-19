import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import Files
import Script

## Verified native documentation rendering. The renderer owns parsing and presentation.
Docs := [].{

	## The reviewed asset for a supported host, from tools-0.1.0-rc.1/sha256sums.txt.
	asset : Str, Str -> Try({ name : Str, sha256 : Str }, [UnsupportedDocsHost])
	asset = |system, machine| match (system, machine) {
		("Linux", "x86_64") => Ok({ name: "roc-docs-x86_64-linux", sha256: "969b94deb3158e9df231b989985e87225578879e9b6f7fb9f4ab46b28af4d586" })
		("Linux", "aarch64") => Ok({ name: "roc-docs-aarch64-linux", sha256: "008438ab3fce377cd7c3b572da72d02b3f72fe79345bc171d221bc0f054a70b2" })
		("Darwin", "arm64") => Ok({ name: "roc-docs-aarch64-darwin", sha256: "8068974f7f2c22033f12ca537e2bf5658afb4554ee2f51b75d2e0e4376495a1a" })
		_ => Err(UnsupportedDocsHost)
	}

	## Verify cached or supplied bytes on every use; download and verify before chmod.
	renderer! = || {
		uname = Script.command("uname")
		selection = asset(uname.output!(["-s"])?, uname.output!(["-m"])?)?
		cache = Path.absolute!(".roc-time-tmp/tools/tools-0.1.0-rc.1")?
		Path.create_all!(cache)?
		binary = Path.utf8(Script.env_str!("ROC_DOCS_BINARY") ?? Path.display(Path.join(cache, selection.name)))
		if !Path.exists!(binary)? {
			pending = Path.join(cache, "${selection.name}.download")
			Cmd.new("curl").args_str([
				"--silent",
				"--show-error",
				"--location",
				"--fail",
				"--retry",
				"2",
				"https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.1.0-rc.1/${selection.name}",
				"--output",
				Path.display(pending),
			]).exec_cmd!()?
			verify_digest!(pending, selection.sha256)?
			Path.rename!(pending, binary)?
		}
		verify_digest!(binary, selection.sha256)?
		Cmd.new("chmod").args(["+x", Path.to_os_str(binary)]).exec_cmd!()?
		Ok(Script.command(Path.to_os_str(Path.absolute!(binary)?)))
	}

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

verify_digest! = |path, expected| {
	digest = Script.command("sha256sum").output!([Path.to_os_str(path)])?
	match Str.split_on(digest, " ") {
		[actual, ..] if actual == expected => Ok({})
		_ => Script.fail!("native documentation renderer SHA-256 mismatch: ${Path.display(path)}")
	}
}

expect Docs.asset("Linux", "riscv64") == Err(UnsupportedDocsHost)
