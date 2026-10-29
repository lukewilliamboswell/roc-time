import cli.Env
import cli.OsStr
import cli.Path
import Files
import OracleStages
import Script
import ZoneDistribution

## Verify real generated providers through the public core adapter. All
## verification sources/binaries live outside the package under .roc-time-tmp.
ZoneVerification := [].{
	integrity! : Path => Try(ZoneDistribution.Manifest, _)
	integrity! = |directory| {
		manifest : ZoneDistribution.Manifest
		manifest = Json.parse(Path.read_utf8!(Path.join(directory, "manifest.json"))?)?
		ZoneDistribution.validate_metadata(manifest)?
		ZoneDistribution.validate_header(Path.read_utf8!(Path.join(directory, "main.roc"))?)?
		adapter = match manifest.generator_adapter_sha256 {
			Ok(expected) => ("scripts/generate_zone_database.roc", expected)
			Err(Missing) => ("scripts/generate_zone_database.py", manifest.generator_sha256)
		}
		if hash!(Path.utf8(adapter.0))? != adapter.1 {
			return Err(GeneratorIntegrity)
		}
		match manifest.reference_adapter_sha256 {
			Ok(expected) => if hash!(Path.utf8("scripts/reference_zone_database.py"))? != expected {
				return Err(ReferenceIntegrity)
			}
			Err(Missing) => {}
		}
		match manifest.generator_adapter_sources {
			Ok(sources) => {
				if sources.len() != ZoneDistribution.source_files.len() or ZoneDistribution.source_files.any(|file| !sources.contains(file)) {
					return Err(GeneratorSourceInventory)
				}
				for (file, expected) in sources.to_list() {
					if hash!(Path.utf8(file))? != expected {
						return Err(GeneratorSourceIntegrity(file))
					}
				}
			}
			Err(Missing) => {}
		}
		if Path.read_bytes!("tzdb/Database.roc")? != Path.read_bytes!(Path.join(directory, "Database.roc"))? {
			return Err(ProviderImplementationIntegrity)
		}
		expected_files = manifest.files.keys().concat(["manifest.json", "main.roc"])
		actual = Path.list!(directory)?
		if actual.len() != expected_files.len() or actual.any(|path| !expected_files.contains(Files.name(path))) {
			return Err(PackageInventory)
		}
		for (name, expected) in manifest.files.to_list() {
			if name.contains("/") or name.contains("\\") or name == "." or name == ".." {
				return Err(PackageInventory)
			}
			file = Path.join(directory, name)
			if Path.type!(file)? != IsFile or hash!(file)? != expected {
				return Err(ArtifactIntegrity(name))
			}
		}
		Ok(manifest)
	}
	verify! : { directory : Path, manifest : ZoneDistribution.Manifest, compiler : Script.Command } => Try({}, _)
	verify! = |{ directory, manifest, compiler }| {
		work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "zone-provider-")?
		core = relative!(work, Path.absolute!("package/main.roc")?)?
		database = relative!(work, Path.join(Path.absolute!(directory)?, "main.roc"))?
		names : List(Str)
		names = sort_names(manifest.names.keys())
		expectations : Dict(Str, { count : U64, checksum : I64 })
		expectations = manifest.transition_expectations
		var $cases = []
		for name in sort_names(expectations.keys()) {
			expected = expectations.get(name)?
			$cases = $cases.append("   ${Json.to_str(name)} => { count: ${expected.count.to_str()}.U64, checksum: ${expected.checksum.to_str()}.I64 }")
		}
		var $source = Path.read_utf8!("scripts/templates/zone-verify.roc.txt")?
		for (marker, value) in [
			("@DATABASE@", Json.to_str(database)),
			("@CORE@", Json.to_str(core)),
			("@NAMES@", Json.to_str(names)),
			("@VERSION@", Json.to_str(manifest.source_version)),
			("@PROFILE@", Json.to_str(manifest.profile)),
			("@START@", manifest.start_second.to_str()),
			("@END@", manifest.end_second.to_str()),
			("@CASES@", Str.join_with($cases, "\n")),
		] {
			if $source.split_on(marker).len() != 2 {
				return Err(VerificationTemplate(marker))
			}
			$source = Str.join_with($source.split_on(marker), value)
		}
		Path.write_utf8!(Path.join(work, "main.roc"), $source)?
		program = OsStr.display(compiler.program())
		_ = OracleStages.run!({
			command: [program, "check", "main.roc"],
			cwd: work,
			logs: work,
			label: "check",
			timeout_ms: 180000,
		})?
		binary = Path.join(work, "verify")
		_ = OracleStages.run!({
			command: [program, "build", "main.roc", "--output=${Path.display(binary)}"],
			cwd: work,
			logs: work,
			label: "build",
			timeout_ms: 180000,
		})?
		result = OracleStages.run!({
			command: [Path.display(binary)],
			cwd: work,
			logs: work,
			label: "run",
			timeout_ms: 180000,
		})?
		if result.stdout != "PASS generated database\n" {
			return Err(MissingGeneratedProviderResult)
		}
		Script.info!({
			label: "PASS",
			message: "${manifest.zone_names.to_str()} names, all retained transitions and adjacent microsecond boundaries; ${Path.display(work)}",
		})
	}
}

hash! : Path => Try(Str, _)
hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()

relative! : Path, Path => Try(Str, _)
relative! = |directory, file| Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(directory)}"), Path.to_os_str(file)])

sort_names : List(Str) -> List(Str)
sort_names = |names| Files.sort_paths(names.map(Path.utf8)).map(Path.display)
