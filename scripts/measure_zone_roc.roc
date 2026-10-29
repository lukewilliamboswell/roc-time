#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.Monotonic
import cli.OsStr
import cli.Path
import src/Script
import src/ZoneArchive
import src/ZoneMeasurement
import src/ZonePrototype

selected = ["Australia/Melbourne", "America/New_York", "Europe/London", "Pacific/Apia"]

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run measure-zone-roc -- [WHEEL] [--smoke] [--samples 1..10] [--encoding columns|tzif]")
	}
	options = ZonePrototype.parse(args.map(OsStr.display))?
	wheel = Path.absolute!(Path.utf8(if (options.wheel.is_empty()) ".roc-time-tmp/measurement-smoke/tzdata.whl" else options.wheel))?
	if !Path.exists!(wheel)? {
		if !options.wheel.is_empty() {
			return Err(MissingWheel)
		}
		Path.create_all!(".roc-time-tmp/measurement-smoke")?
		Cmd.new("curl").args(["--fail", "--location", "--max-time", "30", "--max-filesize", "1048576", OsStr.from_str(ZoneArchive.url), "--output", Path.to_os_str(wheel)]).timeout_ms(40000).exec_cmd!()?
	}
	if size!(wheel)? > 1048576 or hash!(wheel)? != ZoneArchive.sha256 {
		return Err(WheelIntegrity)
	}
	compiler = Script.roc_nightly!()?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "zone-roc-measure-")?
	version = compiler.output!(["version"])?
	system = Script.command("uname").output!(["-s"])?
	python = Script.env_str!("PYTHON") ?? "python3"
	# This retained reference only decodes CPython's TZif columns. It does not
	# build Roc code, bless expectations from roc-time, or supervise processes.
	reference = Cmd.new_str(python).args_str(["scripts/reference_zone_payloads.py", Path.display(wheel), if (options.smoke) "smoke" else "full"]).timeout_ms(60000).output_limit(8388608).stdout(Capture).stderr(Capture).run!()?
	Path.write_bytes!(Path.join(work, "reference.json"), reference.stdout_bytes)?
	Path.write_bytes!(Path.join(work, "reference.stderr"), reference.stderr_bytes)?
	if reference.status != Exited(0) {
		return Err(ReferenceDecoderFailed)
	}
	entries : List(ZonePrototype.Entry)
	entries = Json.parse(Str.from_utf8(reference.stdout_bytes)?)?
	global = ZonePrototype.export(entries, options.encoding)?
	subset = ZonePrototype.export(entries.keep_if(|entry| selected.contains(entry.name)), options.encoding)?
	if options.smoke and global.names.get("Fixture/MelbourneAlias")?.0 != global.names.get("Australia/Melbourne")?.0 {
		return Err(MissingDeduplication)
	}
	var $package_measurements = Dict.empty()
	for (kind, generated) in [("global", global), ("subset", subset)] {
		directory = Path.join(work, kind)
		Path.create_all!(directory)?
		for file in generated.files {
			Path.write_utf8!(Path.join(directory, file.name), file.source)?
		}
		bundle_dir = Path.join(directory, "bundle")
		Path.create_all!(bundle_dir)?
		_ = execute!([OsStr.display(compiler.program()), "bundle"].concat(generated.files.map(|file| file.name)).concat(["--output-dir", Path.display(bundle_dir)]), directory, work, "bundle-${kind}")?
		bundles = Path.list!(bundle_dir)?.keep_if(|path| Path.display(path).ends_with(".tar.zst"))
		bundle = match bundles {
			[one] => one
			_ => return Err(MissingBundle)
		}
		$package_measurements = $package_measurements.insert(kind, { roc_source_bytes: generated.files.fold(0.U64, |sum, file| sum + file.source.count_utf8_bytes()), bundle_bytes: size!(bundle)?, module_count: generated.files.len() })
	}
	template = Path.read_utf8!(Path.utf8("scripts/templates/zone-${options.encoding}.roc.txt"))?
	var $applications = Dict.empty()
	for kind in ["core_only", "static_global", "dynamic_global", "dynamic_subset"] {
		directory = Path.join(work, kind)
		Path.create_all!(directory)?
		source = if kind == "core_only" {
			core = Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(directory)}"), Path.to_os_str(Path.absolute!("package/main.roc")?)])?
			"app [main!] { time: ${Json.to_str(core)} }\nimport time.PosixBoundary\nmain! = |_args| { echo!(Str.inspect(PosixBoundary.from_microseconds(42)))\n Ok({}) }\n"
		} else {
			provider = if (kind == "dynamic_subset") "subset" else "global"
			type_name = if (kind == "static_global") "Melbourne" else "Lookup"
			body = Str.join_with(template.split_on("PAYLOAD"), if (kind == "static_global") "data = Melbourne.data" else "data = Lookup.get($name)?")
			"app [main!] { db: \"../${provider}/main.roc\" }\nimport db.${type_name}\n${body}"
		}
		Path.write_utf8!(Path.join(directory, "main.roc"), source)?
		_ = execute!([OsStr.display(compiler.program()), "check", "main.roc"], directory, work, "check-${kind}")?
		binary = Path.join(directory, "native")
		var $builds = []
		for sample in (0.U64).until(options.samples) {
			args_build = [OsStr.display(compiler.program()), "build", "main.roc", "--no-cache", "--output=${Path.display(binary)}"]
			command = if (system == "Darwin") ["/usr/bin/time", "-l"].concat(args_build) else args_build
			result = execute!(command, directory, work, "build-${kind}-${sample.to_str()}")?
			$builds = $builds.append({ command, seconds: result.seconds, compiler_peak_rss_bytes: ZoneMeasurement.peak_rss(result.stderr)?, binary_bytes: size!(binary)? })
		}
		var $outputs = Dict.empty()
		names = if (["core_only", "static_global"].contains(kind)) ["Australia/Melbourne"] else selected
		for name in names {
			result = execute!([Path.display(binary), name], directory, work, "run-${kind}-${Str.join_with(name.split_on("/"), "-")}")?
			expected = if (kind == "core_only") "PosixBoundary(42 microseconds)" else ZonePrototype.expected(name, (if (kind == "dynamic_subset") subset.names else global.names).get(name)?.1, options.encoding)?
			if result.stdout != expected {
				return Script.fail!("observable checksum mismatch ${kind}/${name}: ${result.stdout}")
			}
			$outputs = $outputs.insert(name, result.stdout.trim())
		}
		$applications = $applications.insert(kind, { uncached_builds: $builds, observable_outputs: $outputs })
		report = { compiler: version, host: Script.command("uname").output!(["-s", "-r", "-m"])?, wheel_sha256: ZoneArchive.sha256, samples: options.samples, smoke: options.smoke, encoding: options.encoding, script_sha256: hash!(Path.utf8("scripts/measure_zone_roc.roc"))?, reference_decoder_sha256: hash!(Path.utf8("scripts/reference_zone_payloads.py"))?, representation: "one module per byte-distinct TZif; columns use times I64, indices U8, offsets I32, footer Str; tzif uses original bytes U8; dynamic match lookup with aliases", limits: "Prototype storage only, not a full provider or TZif adapter. TZif bytes include fields omitted by columns; no runtime parsing cost measured. No footer expansion, schema import, construction allocation or retained-memory measurement. OS/compiler caches may be warm; --no-cache disables Roc cache for uncached builds. Native default backend only.", package_measurements: $package_measurements, applications: $applications }
		Path.write_utf8!(Path.join(work, "report.json"), Json.to_str_try(report)?)?
		Script.info!("MEASURED", kind)?
	}
	Script.info!("EVIDENCE", "${Path.display(work)}/report.json")
}

execute! = |command, cwd, logs, label| {
	before = Monotonic.now!()
	result = Cmd.new_str(command.first()?).args_str(command.drop_first(1)).cwd(cwd).timeout_ms(180000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
	seconds = (Monotonic.now!() - before).to_f64() / 1000000000
	Path.write_bytes!(Path.join(logs, "${label}.stdout"), result.stdout_bytes)?
	Path.write_bytes!(Path.join(logs, "${label}.stderr"), result.stderr_bytes)?
	stdout = Str.from_utf8(result.stdout_bytes)?
	stderr = Str.from_utf8(result.stderr_bytes)?
	if result.status != Exited(0) {
		return Script.fail!("${label} failed: ${stderr}")
	}
	Ok({ stdout, stderr, seconds })
}

size! = |path| U64.from_str(Script.command("wc").output!(["-c", Path.to_os_str(path)])?.trim().split_on(" ").first()?)

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
