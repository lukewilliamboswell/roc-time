#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import src/BenchmarkOptions
import src/BenchmarkProcess
import src/ChronoBenchmark
import src/ComparisonBenchmark
import src/ComparisonOptions
import src/Script
main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run benchmark-comparison -- [--fetch] [--smoke] [--iterations N] [--warmups N] [--samples N] [--rounds N] [--profile microseconds|seconds|both] [--cpu N]; PYTHON_BENCH selects pinned CPython")
	}
	options = ComparisonOptions.parse(args.map(OsStr.display))?
	context = ComparisonBenchmark.prepare!(options)?
	profiles = [("microseconds", "benchmarks/chrono/corpus.jsonl"), ("seconds", "benchmarks/comparison/seconds.jsonl")].keep_if(|(name, _)| options.profile == "both" or options.profile == name)
	var $results = []
	var $limitations = []
	for (profile, corpus) in profiles {
		reference = ChronoBenchmark.reference!(Path.utf8(corpus), options.iterations, context.work)?
		active = if profile == "microseconds" {
			command = ComparisonBenchmark.command(context, "tempo", ["verify", "1", "0", "0", "1900-02-28T01:13:17.027183-03:30"])?
			outcome = Cmd.new_str(command.first()?).args_str(command.drop_first(1)).cwd(context.root).manage_tree(Bool.True).timeout_ms(30000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
			stderr = Str.from_utf8(outcome.stderr_bytes)?
			Path.write_bytes!(Path.join(context.work, "tempo-fractional-offset.stderr"), outcome.stderr_bytes)?
			match outcome.status {
				Exited(code) if code != 0 => {}
				_ => return Err(TempoLimitationChanged)
			}
			if !stderr.contains("Tempo.ParseError") or !stderr.contains(".027183-03:30") {
				return Err(TempoLimitationChanged)
			}
			$limitations = $limitations.append({ library: "tempo", profile, reason: stderr })
			ComparisonBenchmark.libraries.keep_if(|name| name != "tempo")
		} else ComparisonBenchmark.libraries
		for name in active {
			expected_lines = reference.cases.map(
				|case| {
					suffix = if (name == "tempo") "" else "|${if (name == "roc-time" and profile == "seconds") case.text else case.canonical}"
					"${case.day.to_str()}|${case.microseconds.to_str()}${suffix}\n"
				},
			)
			expected = Str.join_with(expected_lines, "")
			output = execute!(context, name, "verify", 1, 0, 0, reference.cases, "${profile}-${name}-verify")?
			if output.stdout != expected {
				return Err(ComparisonOracleMismatch(profile, name))
			}
		}
		Script.info!("PASS", "${profile}: independent per-case oracle and harness negative controls")?
		modes = BenchmarkOptions.modes.keep_if(|mode| profile == "microseconds" or !["format", "end_to_end"].contains(mode))
		for round in (0.U64).to(options.rounds - 1) {
			for (mode, index) in modes.map_with_index(|mode, index| (mode, index)) {
				names = ComparisonOptions.order(active.keep_if(|name| ComparisonBenchmark.supports(name, mode)), round, index)
				for name in names {
					output = execute!(context, name, mode, options.iterations, options.warmups, options.samples, reference.cases, "${profile}-${round.to_str()}-${mode}-${name}")?
					elapsed = BenchmarkOptions.samples(output.stdout, options.samples, reference.checksums.get(mode)?)?
					value = BenchmarkOptions.median(elapsed)? / options.iterations.to_f64()
					$results = $results.append({ profile, round: round + 1, library: name, workload: mode, nanoseconds: elapsed, median_ns_per_operation: value })
					Script.info!(name, "${profile} ${mode}: ${value.to_str()} ns/op${if (options.smoke) " (smoke; not performance evidence)" else ""}")?
				}
			}
		}
	}
	var $binaries = Dict.empty()
	for (name, path) in ComparisonBenchmark.native(context) {
		$binaries = $binaries.insert(name, hash!(path)?)
	}
	var $sources = Dict.empty()
	for folder in ["benchmarks/comparison", "benchmarks/chrono", "scripts/src"] {
		$sources = collect_sources!(Path.utf8(folder), $sources)?
	}
	for file in ["scripts/benchmark_comparison.roc", "scripts/benchmark_chrono.roc", "scripts/reference_benchmarks.py"] {
		$sources = $sources.insert(file, hash!(Path.utf8(file))?)
	}
	var $corpora = Dict.empty()
	for (name, path) in profiles {
		$corpora = $corpora.insert(name, hash!(Path.utf8(path))?)
	}
	var $governors = Dict.empty()
	for cpu in context.affinity {
		path = Path.utf8("/sys/devices/system/cpu/cpu${cpu.to_str()}/cpufreq/scaling_governor")
		if Path.exists!(path)? {
			$governors = $governors.insert(cpu.to_str(), Path.read_utf8!(path)?.trim())
		}
	}
	extension = BenchmarkProcess.run!([context.python, "-c", "import ciso8601; print(ciso8601.__file__)"], context.root, context.work, "ciso-extension", context.environment, 30000)?.stdout.trim()
	report = { scope: "bounded Gregorian/fixed-offset throughput; no library-wide ranking or memory claims", options, versions: context.versions, dependencies: context.pins, build_targets: { roc_target: "x64musl/speed", rust: "x86_64-unknown-linux-musl/release", go: "linux/amd64 CGO_ENABLED=0" }, binary_sha256: $binaries, python_extension_sha256: hash!(Path.utf8(extension))?, zig: Script.command(OsStr.from_str(Script.env_str!("ZIG") ?? "zig")).output!(["version"])?, host_platform: Script.command("uname").output!(["-a"])?, cpuinfo: Path.read_utf8!("/proc/cpuinfo")?.split_on("\n\n").first()?, affinity: context.affinity, loadavg_after: Path.read_utf8!("/proc/loadavg")?.trim(), cpu_governors: $governors, git_revision: Script.command("git").output!(["rev-parse", "HEAD"])?, working_tree: Script.command("git").output!(["status", "--short"])?, source_sha256: $sources, corpus_sha256: $corpora, limitations: $limitations, results: $results }
	stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%S.%NZ"])?
	destination = Path.join(context.work, "results-${stamp}.json")
	Path.write_utf8!(destination, Json.to_str_try(report)?)?
	Script.info!("EVIDENCE", Path.display(destination))
}

execute! : ComparisonBenchmark.Context, Str, Str, U64, U64, U64, List(ChronoBenchmark.Case), Str => Try({ stdout : Str, stderr : Str }, _)
execute! = |context, name, mode, iterations, warmups, samples, cases, label| {
	command = ComparisonBenchmark.command(context, name, [mode, iterations.to_str(), warmups.to_str(), samples.to_str()].concat(cases.map(|case| case.text)))?
	BenchmarkProcess.run!(command, context.root, context.work, label, context.environment, 300000)
}

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()

collect_sources! = |folder, sources| {
	var $sources = sources
	for path in Path.list!(folder)? {
		name = Path.filename(path)?.to_str()?
		if !["target", "targets"].contains(name) {
			if Path.is_dir!(path)? {
				$sources = collect_sources!(path, $sources)?
			} else {
				$sources = $sources.insert(Path.display(path), hash!(path)?)
			}
		}
	}
	Ok($sources)
}
