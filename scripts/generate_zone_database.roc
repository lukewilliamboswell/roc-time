#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/Script
import src/ZoneDistribution
import src/ZoneVerification

main! = |args| {
	(wheel_arg, output_arg, verify) = match args.map(OsStr.display) {
		[wheel, output] => (wheel, output, Bool.False)
		[wheel, output, "--verify"] => (wheel, output, Bool.True)
		_ => return Script.fail!("usage: blueprint run generate-zone-database -- WHEEL NEW_DIRECTORY [--verify]; ROC_NIGHTLY selects the package compiler")
	}
	wheel = Path.absolute!(Path.utf8(wheel_arg))?
	output = Path.absolute!(Path.utf8(output_arg))?
	if !Path.display(output).starts_with("/") {
		return Err(UnsupportedHostPath)
	}
	if Path.exists!(output)? {
		return Err(OutputExists(Path.display(output)))
	}
	digest = hash!(wheel)?
	if digest != ZoneDistribution.wheel_sha256 {
		return Err(WheelIntegrity)
	}
	zi = Script.command("unzip").output!(["-p", Path.to_os_str(wheel), "tzdata/zoneinfo/tzdata.zi"])?
	module_text = Script.command("unzip").output!(["-p", Path.to_os_str(wheel), "tzdata/__init__.py"])?
	ZoneDistribution.validate_source("${zi}\n", module_text)?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "zone-generation-")?
	python = Script.env_str!("PYTHON") ?? "python3"
	reference_result = Cmd.new_str(python).args_str(["scripts/reference_zone_database.py", Path.display(wheel)]).timeout_ms(180000).manage_tree(Bool.True).output_limit(16777216).stdout(Capture).stderr(Capture).run!()?
	Path.write_bytes!(Path.join(work, "reference.json"), reference_result.stdout_bytes)?
	Path.write_bytes!(Path.join(work, "reference.stderr"), reference_result.stderr_bytes)?
	if reference_result.status != Exited(0) {
		return Err(ReferenceModelFailed(Path.display(work)))
	}
	reference : ZoneDistribution.Reference
	reference = Json.parse(Str.from_utf8(reference_result.stdout_bytes)?)?
	assets = ZoneDistribution.assets(reference)?
	if reference.licenses.len() != 2 or ["LICENSE.txt", "LICENSE_APACHE.txt"].any(|name| reference.licenses.count_if(|license| license.name == name) != 1) or reference.licenses.any(|license| license.bytes.len() > 65536) {
		return Err(ReferenceLicenses)
	}
	parent = Path.utf8(ZoneDistribution.parent_path(Path.display(output)))
	Path.create_all!(parent)?
	Path.create_dir!(output)?
	Path.write_utf8!(Path.join(output, "zones.txt"), assets.zones)?
	Path.write_utf8!(Path.join(output, "names.txt"), assets.names)?
	Path.copy!("tzdb/Database.roc", Path.join(output, "Database.roc"))?
	Path.write_utf8!(Path.join(output, "main.roc"), ZoneDistribution.header)?
	for license in reference.licenses {
		Path.write_bytes!(Path.join(output, license.name), license.bytes)?
	}
	var $files = []
	for name in ["Database.roc", "zones.txt", "names.txt", "LICENSE.txt", "LICENSE_APACHE.txt"] {
		$files = $files.append((name, hash!(Path.join(output, name))?))
	}
	var $sources = []
	for file in ZoneDistribution.source_files {
		$sources = $sources.append((file, hash!(Path.utf8(file))?))
	}
	manifest = ZoneDistribution.manifest(reference.metadata, hash!(Path.utf8("scripts/generate_zone_database.roc"))?, hash!(Path.utf8("scripts/reference_zone_database.py"))?, Dict.from_list($files), Dict.from_list($sources))
	ZoneDistribution.validate_metadata(manifest)?
	Path.write_utf8!(Path.join(output, "manifest.json"), Json.to_str(manifest))?
	_ = ZoneVerification.integrity!(output)?
	if verify {
		compiler = Script.roc_nightly!()?
		ZoneVerification.verify!(output, manifest, compiler)?
	}
	Script.info!("GENERATED", "${manifest.zone_names.to_str()} names, ${manifest.canonical_zones.to_str()} canonical zones, ${manifest.offset_comparisons.to_str()} independent offset comparisons; ${Path.display(output)}")
}

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
