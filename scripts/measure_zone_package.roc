#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.Monotonic
import cli.OsStr
import cli.Path
import src/FixtureHost
import src/NativeMetrics
import src/Script
import src/ZoneMeasurement

Manifest : { names : Dict(Str, Str), transition_expectations : Dict(Str, { count : U64, checksum : I64 }) }

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run measure-zone-package -- [--smoke] [--package DIR]... [--samples 1..10] [--opt dev|speed]")
	}
	options = ZoneMeasurement.parse(args.map(OsStr.display))?
	compiler = Script.roc_nightly!()?
	version = compiler.output!(["version"])?
	target = FixtureHost.build!()?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "zone-package-measure-")?
	original = Path.read_utf8!("tests/zone_database/resource/main.roc")?
	host = Path.display(Path.absolute!("tests/platform/main.roc")?)
	system = Script.command("uname").output!(["-s"])?
	var $measurements = []
	for (number, supplied) in options.directories.map_with_index(|directory, index| (index, directory)) {
		package_directory = Path.absolute!(Path.utf8(supplied))?
		manifest_path = Path.join(package_directory, "manifest.json")
		manifest : Manifest
		manifest = Json.parse(Path.read_utf8!(manifest_path)?)?
		for mode in ["static", "dynamic"] {
			workspace = Path.join(work, "${number.to_str()}-${mode}")
			Path.create_all!(workspace)?
			host_import = Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(workspace)}"), OsStr.from_str(host)])?
			provider_import = Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(workspace)}"), Path.to_os_str(Path.join(package_directory, "main.roc"))])?
			source = ZoneMeasurement.source(original, host_import, provider_import, mode == "static", options.smoke)?
			Path.write_utf8!(Path.join(workspace, "main.roc"), source)?
			binary = Path.join(workspace, "native")
			var $builds = []
			for sample in (0.U64).until(options.samples) {
				build_args = ["build", "main.roc", "--no-cache", "--debug", "--target=${target}", "--opt=${options.optimize}", "--output=${Path.display(binary)}"]
				command = if (system == "Darwin") ["/usr/bin/time", "-l", OsStr.display(compiler.program())].concat(build_args) else [OsStr.display(compiler.program())].concat(build_args)
				before = Monotonic.now!()
				output = Cmd.new_str(command.first()?).args_str(command.drop_first(1)).cwd(workspace).timeout_ms(180000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
				seconds = (Monotonic.now!() - before).to_f64() / 1000000000
				stdout = Str.from_utf8(output.stdout_bytes)?
				stderr = Str.from_utf8(output.stderr_bytes)?
				Path.write_utf8!(Path.join(workspace, "build-${sample.to_str()}.log"), "${stdout}${stderr}")?
				if output.status != Exited(0) {
					return Script.fail!("zone package build failed: ${stderr}")
				}
				compiler_peak_rss_bytes = ZoneMeasurement.peak_rss(stderr)?
				binary_bytes = size!(binary)?
				$builds = $builds.append({ command, seconds, compiler_peak_rss_bytes, binary_bytes })
			}
			var $observed = Dict.empty()
			names = if (mode == "static") ["Australia/Melbourne"] else ["Australia/Melbourne", "US/Eastern", "Pacific/Apia", "Etc/UTC"]
			for name in names {
				output = Cmd.new(Path.to_os_str(binary)).args_str([name]).timeout_ms(10000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
				stdout = Str.from_utf8(output.stdout_bytes)?
				metrics = NativeMetrics.parse(Str.from_utf8(output.stderr_bytes)?)?
				canonical = manifest.names.get(name)?
				expected = manifest.transition_expectations.get(canonical)?
				if output.status != Exited(0) or stdout != "${canonical}|${expected.checksum.to_str()}\n" or metrics.work.len() != 2 or metrics.work.get(1)? != expected.count {
					return Err(ObservableLookupMismatch(name))
				}
				$observed = $observed.insert(name, { stdout, metrics })
			}
			$measurements = $measurements.append({ package_directory: Path.display(package_directory), mode, manifest_sha256: hash!(manifest_path)?, builds: $builds, observed: $observed })
			report = { smoke: options.smoke, compiler: version, target, backend: "native", optimize: options.optimize, host: Script.command("uname").output!(["-s", "-r", "-m"])?, samples: options.samples, script_sha256: hash!(Path.utf8("scripts/measure_zone_package.roc"))?, limits: "Uncached builds, no warmup; OS caches may be warm. Compiler wall time/RSS and binary size only, not runtime latency or retained memory. Lookup counters exclude argument preparation, core adaptation and output formatting. Immutable source data may be shared. Each process performs one lookup and consumes its transitions.", measurements: $measurements }
			Path.write_utf8!(Path.join(work, "report.json"), Json.to_str_try(report)?)?
			Script.info!("MEASURED", "${Path.display(package_directory)} ${mode}")?
		}
	}
	Script.info!("EVIDENCE", "${Path.display(work)}/report.json")
}

size! = |path| U64.from_str(Script.command("wc").output!(["-c", Path.to_os_str(path)])?.trim().split_on(" ").first()?)

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
