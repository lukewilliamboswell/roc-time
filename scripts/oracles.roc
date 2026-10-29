#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Env
import cli.Monotonic
import cli.OsStr
import cli.Path
import src/Files
import src/FixtureHost
import src/OracleCases
import src/OracleManifest
import src/OracleOptions
import src/OracleReplay
import src/OracleStages
import src/Script

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run oracles -- [--oracle gregorian|julian|zones|calendar_pattern|rfc_date|rfc_timed] [--workers 1..16]; reference refresh is a separate explicit generator command")
	}
	options = OracleOptions.parse(args.map(OsStr.display))?
	compiler = Script.roc_nightly!()?
	target = FixtureHost.build!()?
	parent = Path.absolute!(Path.utf8(Script.env_str!("ROC_TIME_TMPDIR") ?? ".roc-time-tmp"))?
	Path.create_all!(Path.join(parent, "oracles"))?
	for name in options.names {
		manifest = OracleManifest.parse(Path.read_utf8!(Path.utf8("tests/oracles/${name}-manifest.toml"))?, name)?
		corpus = Path.utf8("tests/oracles/${name}.jsonl")
		require_hash!(corpus, manifest.corpus_sha256)?
		source = Path.utf8("tests/oracle_${name}")
		smoke = Path.join(source, if (name == "zones") "Cases.roc" else "SmokeCases.roc")
		require_hash!(smoke, manifest.smoke_sha256)?
		generator = match name {
			"gregorian" => "scripts/oracles.py"
			"julian" => "scripts/oracles.py"
			"zones" => "scripts/generate_zone_oracle.py"
			"calendar_pattern" => "scripts/generate_pattern_oracle.py"
			"rfc_date" => "scripts/generate_rfc_date_oracle.py"
			"rfc_timed" => "scripts/generate_rfc_timed_oracle.py"
			_ => ""
		}
		if !generator.is_empty() {
			require_hash!(Path.utf8(generator), manifest.generator_adapter_sha256)?
		}
		if name == "calendar_pattern" {
			gaps = Path.utf8("tests/oracles/calendar_pattern-reference-gaps.jsonl")
			require_hash!(gaps, manifest.gap_sha256)?
			text = Path.read_utf8!(gaps)?
			rows = if (text.ends_with("\n")) text.drop_suffix("\n").split_on("\n") else text.split_on("\n")
			if rows.len() != manifest.gap_count {
				return Err(ReferenceGapCount)
			}
		}
		# Admit the file size before retaining its contents in the host.
		size = U64.from_str(Script.command("wc").output!(["-c", Path.to_os_str(corpus)])?.trim().split_on(" ").first()?)?
		if size > 4194304 {
			return Err(CorpusSize)
		}
		cases = OracleCases.load(Path.read_utf8!(corpus)?, manifest.case_count, name)?
		session = Env.create_temp_dir_in!(Path.join(parent, "oracles"), "${name}-")?
		var $driver_hashes = []
		for file in Files.sort_paths(Files.all_roc_files!(source)?) {
			relative = Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(Path.absolute!(source)?)}"), Path.to_os_str(Path.absolute!(file)?)])?
			destination = Path.join(session, relative)
			parts = relative.split_on("/").drop_last(1)
			directory = if (parts.is_empty()) session else Path.join(session, Str.join_with(parts, "/"))
			Path.create_all!(directory)?
			core = relative!(directory, Path.absolute!("package/main.roc")?)?
			host = relative!(directory, Path.absolute!("tests/platform/main.roc")?)?
			Path.write_utf8!(destination, OracleOptions.rewrite(Path.read_utf8!(file)?, core, host))?
			$driver_hashes = $driver_hashes.append((relative, hash!(file)?))
		}
		program = OsStr.display(compiler.program())
		version = OracleStages.run!([program, "version"], session, "version")?.stdout.trim()
		started = Monotonic.now!()
		_ = OracleStages.run!([program, "check", "main.roc"], session, "check")?
		_ = OracleStages.run!([program, "test", "main.roc"], session, "comparator-tests")?
		interpreted = OracleStages.run!([program, "main.roc"], session, "interpret")?
		if interpreted.stdout != "PASS ${manifest.smoke_case_count.to_str()} oracle cases\n" {
			return Err(InterpreterSmoke(name))
		}
		binary = Path.join(session, "oracle")
		_ = OracleStages.run!([program, "check", "native/main.roc"], session, "native-check")?
		_ = OracleStages.run!([program, "build", "native/main.roc", "--debug", "--target=${target}", "--output=${Path.display(binary)}"], session, "build")?
		first = cases.first()?
		wrong = { ..first, expected: ["deliberately-wrong"] }
		wrong_dir = Path.join(session, "controls/wrong")
		Path.create_all!(wrong_dir)?
		match OracleReplay.one!(binary, wrong, wrong_dir, 5000) {
			Err(OracleCaseFailure(failure)) if failure.kind == Mismatch => {}
			other => return Script.fail!("${name}: comparator failure control ${Str.inspect(other)}")
		}
		invalid = { ..first, operation: "invalid_operation" }
		malformed_dir = Path.join(session, "controls/malformed")
		Path.create_all!(malformed_dir)?
		match OracleReplay.one!(binary, invalid, malformed_dir, 5000) {
			Err(OracleCaseFailure(failure)) if failure.kind == Status => {}
			other => return Script.fail!("${name}: native input failure control ${Str.inspect(other)}")
		}
		match OracleStages.run!([Path.display(binary), first.id, "invalid_operation"].concat(first.input), session, "failure-control") {
			Err(StageStatus(_, Exited(code))) if code != 0 => {}
			other => return Script.fail!("${name}: command failure control ${Str.inspect(other)}")
		}
		results = OracleReplay.replay!(binary, cases, session, options.workers)?
		elapsed = (Monotonic.now!() - started).to_f64() / 1000000000
		counts = results.map(|result| result.allocations)
		var $package_hashes = []
		for file in Files.sort_paths(Files.direct_roc_files!("package")?) {
			$package_hashes = $package_hashes.append((Files.name(file), hash!(file)?))
		}
		var $runner_hashes = []
		for file in ["scripts/oracles.roc", "scripts/src/OracleCases.roc", "scripts/src/OracleManifest.roc", "scripts/src/OracleOptions.roc", "scripts/src/OracleReplay.roc", "scripts/src/OracleStages.roc", "scripts/src/NativeMetrics.roc", "scripts/src/FixtureHost.roc"] {
			$runner_hashes = $runner_hashes.append((file, hash!(Path.utf8(file))?))
		}
		report = { runner_sha256: Dict.from_list($runner_hashes), compiler: version, host: Script.command("uname").output!(["-s", "-r", "-m"])?, target, backend: "native default optimization with --debug; fixed interpreter smoke", case_count: manifest.case_count, workers: options.workers, seconds: elapsed, corpus_sha256: manifest.corpus_sha256, driver_sha256: Dict.from_list($driver_hashes), package_sha256: Dict.from_list($package_hashes), stage_timeout_seconds: 120.U64, stage_output_bytes: 1048576.U64, case_timeout_seconds: 5.U64, case_output_bytes: 16384.U64, allocation_count_range: [counts.min()?, counts.max()?], resource_scope: "whole fixture including argv parsing and observation formatting; not isolated temporal operation", case_timing_scope: "spawn through ordered collection, including queue wait; not per-operation latency" }
		Path.write_utf8!(Path.join(session, "report.json"), Json.to_str_try(report)?)?
		Script.info!("PASS", "${name}: ${manifest.case_count.to_str()} independent JSONL observations; ${elapsed.to_str()}s; ${Path.display(session)}")?
	}
	Ok({})
}

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()

require_hash! = |path, expected| {
	if hash!(path)? != expected {
		return Err(OracleIntegrity(Path.display(path)))
	}
	Ok({})
}

relative! = |directory, file| Script.command("realpath").output!([OsStr.from_str("--relative-to=${Path.display(directory)}"), Path.to_os_str(file)])
