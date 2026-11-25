#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }
import cli.Cmd
import cli.Duration
import cli.OsStr
import cli.Path
import src/BenchmarkEvidence
import src/BenchmarkExpectations
import src/BenchmarkOptions
import src/BenchmarkProcess
import src/BenchmarkTimingCache
import src/ChronoBenchmark
import src/ComparisonBenchmark
import src/ComparisonOptions
import src/OperationalBenchmark
import src/Script
main! : List(OsStr) => Try({}, _)
main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!({
			label: "usage:",
			message: "blueprint run benchmark-comparison; blueprint run benchmark-peers -- [--fetch] [--smoke] [--iterations N] [--warmups N] [--samples N] [--rounds N] [--profile microseconds|seconds|both] [--cpu N]",
		})
	}
	available_profiles = [
		("microseconds", "benchmarks/chrono/corpus.jsonl"),
		("seconds", "benchmarks/comparison/seconds.jsonl"),
	]
	tokens = args.map(OsStr.display)
	peer_args = match tokens {
		["--replay-only"] => {
			replay_dates!(available_profiles, Fixture)?
			return OperationalBenchmark.run!(Replay)
		}
		["--operational"] => return OperationalBenchmark.run!(Measure)
		["--operational", "--review", .. as paths] => return OperationalBenchmark.review!(paths)
		["--operational-peers"] => return OperationalBenchmark.run!(RefreshPeers({ fetch: False }))
		["--operational-peers", "--fetch"] => return OperationalBenchmark.run!(RefreshPeers({ fetch: True }))
		["--refresh-expectations"] => return refresh_expectations!(available_profiles)
		["--review-roc", .. as paths] => return review_roc!(paths)
		["--refresh-peers", .. as rest] => rest
		[] => {
			measure_cached!(available_profiles)?
			return OperationalBenchmark.run!(Measure)
		}
		_ => return Err(ExplicitPeerRefreshRequired)
	}
	options = ComparisonOptions.parse(peer_args)?
	context = ComparisonBenchmark.prepare!(options)?
	standard = options == ComparisonOptions.parse([])?
	identity_before = if (standard) [timing_identity!(options)?] else []
	profiles = available_profiles.keep_if(|(name, _)| options.profile == "both" or options.profile == name)
	var $results = []
	var $limitations = []
	for (profile, corpus) in profiles {
		reference = BenchmarkExpectations.load!({
			profile,
			corpus: Path.utf8(corpus),
			iterations: options.iterations,
		})?
		active = if context.native_mac {
			$limitations = $limitations.append({ library: "tempo", profile, reason: "No reviewed native Tempo runtime pin" })
			ComparisonBenchmark.libraries.keep_if(|name| name != "tempo")
		} else if profile == "microseconds" {
			command = ComparisonBenchmark.command(
				context,
				{
					library: "tempo",
					args: ["verify", "1", "0", "0", "1900-02-28T01:13:17.027183-03:30"],
				},
			)?
			outcome = Cmd.new(OsStr.from_str(command.first()?)).args((command.drop_first(1)).map(OsStr.from_str)).cwd(context.root).manage_tree(Bool.True).timeout(Duration.millis(30000)).output_limit(MaxBytes(1048576)).stdout(Capture).stderr(Capture).run!()?
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
			output = execute!(
				context,
				{
					name,
					mode: "verify",
					iterations: 1,
					warmups: 0,
					samples: 0,
					cases: reference.cases,
					label: "${profile}-${name}-verify",
				},
			)?
			if output.stdout != expected {
				return Err(ComparisonOracleMismatch(profile, name))
			}
		}
		Script.info!({
			label: "PASS",
			message: "${profile}: independent per-case oracle and harness negative controls",
		})?
		modes = BenchmarkOptions.modes.keep_if(|mode| profile == "microseconds" or !["format", "end_to_end"].contains(mode))
		for round in (0.U64).to(options.rounds - 1) {
			for (mode, index) in modes.map_with_index(|mode, index| (mode, index)) {
				names = ComparisonOptions.order({
					names: active.keep_if(
						|name| ComparisonBenchmark.is_supported_workload({
							library: name,
							workload: mode,
						}),
					),
					round,
					index,
				})
				for name in names {
					output = execute!(
						context,
						{
							name,
							mode,
							iterations: options.iterations,
							warmups: options.warmups,
							samples: options.samples,
							cases: reference.cases,
							label: "${profile}-${round.to_str()}-${mode}-${name}",
						},
					)?
					elapsed = BenchmarkOptions.samples(output.stdout, options.samples, reference.checksums.get(mode)?)?
					value = BenchmarkOptions.median(elapsed)? / options.iterations.to_f64()
					$results = $results.append({
						profile,
						round: round + 1,
						library: name,
						workload: mode,
						nanoseconds: elapsed,
						median_ns_per_operation: value,
					})
					Script.info!({
						label: name,
						message: "${profile} ${mode}: ${value.to_str()} ns/op${if (options.smoke) " (smoke; not performance evidence)" else ""}",
					})?
				}
			}
		}
	}
	var $binaries = Dict.empty()
	for { library, binary } in ComparisonBenchmark.native_binaries(context) {
		$binaries = $binaries.insert(library, BenchmarkEvidence.hash!(binary)?)
	}
	var $sources = Dict.empty()
	for folder in ["benchmarks/comparison", "benchmarks/chrono", "scripts/src", "package"] {
		$sources = BenchmarkEvidence.collect_sources!(Path.utf8(folder), $sources)?
	}
	for file in [
		"scripts/benchmark_comparison.roc",
		"scripts/benchmark_chrono.roc",
		"scripts/reference_benchmarks.py",
	] {
		$sources = $sources.insert(file, BenchmarkEvidence.hash!(Path.utf8(file))?)
	}
	var $corpora = Dict.empty()
	for (name, path) in profiles {
		$corpora = $corpora.insert(name, BenchmarkEvidence.hash!(Path.utf8(path))?)
	}
	var $governors = Dict.empty()
	for cpu in context.affinity {
		path = Path.utf8("/sys/devices/system/cpu/cpu${cpu.to_str()}/cpufreq/scaling_governor")
		if Path.exists!(path)? {
			$governors = $governors.insert(cpu.to_str(), Path.read_utf8!(path)?.trim())
		}
	}
	host_details = if context.native_mac {
		hardware = Script.command("system_profiler").output!(["SPHardwareDataType"])?
		Str.join_with(
			hardware.split_on("\n").map(Str.trim).keep_if(
				|line| {
					["Chip:", "Model Identifier:", "Total Number of Cores:"].any(|prefix| line.starts_with(prefix))
				},
			),
			"\n",
		)
	} else Path.read_utf8!("/proc/cpuinfo")?.split_on("\n\n").first()?
	extension = BenchmarkProcess.run!({
		args: [context.python, "-c", "import ciso8601; print(ciso8601.__file__)"],
		cwd: context.root,
		logs: context.work,
		label: "ciso-extension",
		environment: context.environment,
		timeout_ms: 30000,
	})?.stdout.trim()
	report = {
		scope: "bounded Gregorian/fixed-offset throughput; no library-wide ranking or memory claims",
		options,
		versions: context.versions,
		dependencies: context.pins,
		build_targets: {
			roc_target: "${context.chrono.target}/speed",
			rust: "${context.chrono.rust_target}/release",
			go: if (context.native_mac) "darwin/arm64 CGO_ENABLED=0" else "linux/amd64 CGO_ENABLED=0",
		},
		binary_sha256: $binaries,
		python_extension_sha256: BenchmarkEvidence.hash!(Path.utf8(extension))?,
		zig: Script.command(OsStr.from_str(Script.env_str!("ZIG") ?? "zig")).output!(["version"])?,
		host_platform: Script.command("uname").output!(["-a"])?,
		cpuinfo: host_details,
		scheduling: if (context.native_mac) "native scheduler, no affinity override" else "Linux effective affinity recorded",
		affinity: context.affinity,
		loadavg_after: if (context.native_mac) Script.command("uptime").output!([])? else Path.read_utf8!("/proc/loadavg")?.trim(),
		cpu_governors: $governors,
		git_revision: Script.command("git").output!(["rev-parse", "HEAD"])?,
		working_tree: Script.command("git").output!(["status", "--short"])?,
		source_sha256: $sources,
		corpus_sha256: $corpora,
		limitations: $limitations,
		results: $results,
	}
	stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%SZ"])?
	destination = Path.join(context.work, "results-${stamp}.json")
	Path.write_utf8!(destination, Json.to_str_try(report)?)?
	if standard {
		identity = timing_identity!(options)?
		if identity_before != [identity] {
			return Err(InconclusiveReferenceEnvironment)
		}
		required = required_peers(available_profiles, context.native_mac)
		rows = required.map_try(
			|{ profile, workload, library }| {
				samples = $results.keep_if(|row| row.profile == profile and row.workload == workload and row.library == library).fold([], |all, row| all.concat(row.nanoseconds))
				median_ns_per_op = BenchmarkOptions.median(samples)? / options.iterations.to_f64()
				Ok({ profile, workload, library, median_ns_per_op })
			},
		)?
		cache = { identity, rows, versions: context.versions, binaries: $binaries.insert("ciso8601", report.python_extension_sha256) }
		BenchmarkTimingCache.admit(cache, identity, required)?
		candidate = Path.join(context.work, "peer-baseline-candidate.json")
		Path.write_utf8!(candidate, "${Json.to_str_try(cache)?}\n")?
		Script.info!({ label: "REVIEW", message: Path.display(candidate) })?
		Script.info!({ label: "SHA256", message: BenchmarkEvidence.hash!(candidate)? })?
		workloads = required.map(|{ profile, workload, .. }| (profile, workload)).fold([], |unique, key| if (unique.contains(key)) unique else unique.append(key))
		for (profile, workload) in workloads {
			roc_samples = $results.keep_if(|row| row.profile == profile and row.workload == workload and row.library == "roc-time").fold([], |all, row| all.concat(row.nanoseconds))
			median = BenchmarkOptions.median(roc_samples)? / options.iterations.to_f64()
			peer = BenchmarkTimingCache.fastest(cache, { profile, workload })?
			ratio = median / peer.median_ns_per_op
			status = if (ratio <= 1.50) "MEETS" else "MISS"
			Script.info!({ label: status, message: "${profile} ${workload}: ${median.to_str()} ns/op, ${ratio.to_str()}× ${peer.library}" })?
		}
	}
	Script.info!({
		label: "EVIDENCE",
		message: Path.display(destination),
	})
}

required_peers : List((Str, Str)), Bool -> List({ profile : Str, workload : Str, library : Str })
required_peers = |profiles, native_mac| {
	profiles.fold(
		[],
		|rows, (profile, _)| {
			modes = if (profile == "seconds") ["parse"] else ["construct", "date_to_day", "roundtrip", "add_days", "parse", "format", "end_to_end"]
			modes.fold(
				rows,
				|all, workload| {
					peers = ComparisonBenchmark.libraries.keep_if(
						|library| {
							library != "roc-time" and (library != "tempo" or (!native_mac and profile == "seconds")) and ComparisonBenchmark.is_supported_workload({ library, workload })
						},
					).map(|library| { profile, workload, library })
					all.concat(peers)
				},
			)
		},
	)
}

timing_identity! : ComparisonOptions.Options => Try(BenchmarkTimingCache.Identity, _)
timing_identity! = |options| {
	host = BenchmarkEvidence.host!()?

	files = [
		"benchmarks/chrono/Cargo.toml",
		"benchmarks/chrono/Cargo.lock",
		"benchmarks/chrono/rust-version",
		"benchmarks/chrono/src/main.rs",
		"benchmarks/chrono/corpus.jsonl",
		"benchmarks/comparison/seconds.jsonl",
		"benchmarks/comparison/dependencies.json",
		"benchmarks/comparison/go_bench.go",
		"benchmarks/comparison/python_bench.py",
		"benchmarks/comparison/tempo_bench.exs",
		"benchmarks/comparison/rust/Cargo.toml",
		"benchmarks/comparison/rust/Cargo.lock",
		"benchmarks/comparison/rust/src/main.rs",
	]
	hashes = files.map_try!(|file| Ok((file, BenchmarkEvidence.hash!(Path.utf8(file))?)))?
	Ok({
		protocol: "wall-monotonic-rotated-v1/chrono-jiff-release-locked/go-trimpath-cgo0/python-native/complete-record-coordinate-and-bytes",
		host,
		input_sha256: Dict.from_list(hashes),
		iterations: options.iterations,
		warmups: options.warmups,
		samples: options.samples,
		rounds: options.rounds,
	})
}

measure_cached! : List((Str, Str)) => Try({}, _)
measure_cached! = |profiles| {
	baseline = Path.utf8(".roc-time-tmp/benchmark-baselines/peer-baseline.json")
	digest = Path.utf8(".roc-time-tmp/benchmark-baselines/peer-baseline.sha256")
	cache = BenchmarkEvidence.load_peer_baseline!({ baseline, digest })?
	options = ComparisonOptions.parse([])?
	identity = timing_identity!(options)?
	native_mac = Script.command("uname").output!(["-s"])? == "Darwin"
	required = required_peers(profiles, native_mac)
	BenchmarkTimingCache.admit(cache, identity, required)?
	replay_dates!(profiles, Timing)?
	root = Path.absolute!(".")?
	work = Path.absolute!(".roc-time-tmp/benchmark-replay")?
	binary = Path.join(work, "roc-speed")
	before = timing_control!({ binary, cwd: root, logs: work, label: "control-before" })?
	workloads = required.map(|{ profile, workload, .. }| (profile, workload)).fold([], |unique, key| if (unique.contains(key)) unique else unique.append(key))
	compiler = Script.roc_nightly!()?.output!(["version"])?
	reviewed_path = Path.utf8(".roc-time-tmp/benchmark-baselines/roc-baseline.json")
	reviewed = if Path.exists!(reviewed_path)? {
		reference : BenchmarkTimingCache.RocBaseline
		reference = Json.parse(Path.read_utf8!(reviewed_path)?)?
		if reference.identity == identity and reference.compiler == compiler {
			Some(reference)
		} else {
			Script.info!({ label: "BASELINE", message: "Reviewed Roc baseline has a different compiler or protocol identity." })?
			None
		}
	} else {
		Script.info!({ label: "BASELINE", message: "No reviewed Roc baseline for regression comparison." })?
		None
	}
	admit_control(before, reviewed)?
	var $misses = []
	var $regressions = []
	var $results = []
	for (profile, corpus) in profiles {
		reference = BenchmarkExpectations.load!({ profile, corpus: Path.utf8(corpus), iterations: options.iterations })?
		inputs = reference.cases.map(|case| case.text)
		for (_, workload) in workloads.keep_if(|(name, _)| name == profile) {
			var $samples = []
			for round in (1.U64).to(options.rounds) {
				output = BenchmarkProcess.run!({
					args: [Path.display(binary), workload, options.iterations.to_str(), options.warmups.to_str(), options.samples.to_str()].concat(inputs),
					cwd: root,
					logs: work,
					label: "${profile}-${workload}-roc-${round.to_str()}",
					environment: [],
					timeout_ms: 300000,
				})?
				samples = BenchmarkOptions.samples(output.stdout, options.samples, reference.checksums.get(workload)?)?
				$samples = $samples.concat(samples)
			}
			median = BenchmarkOptions.median($samples)? / options.iterations.to_f64()
			peer = BenchmarkTimingCache.fastest(cache, { profile, workload })?
			ratio = median / peer.median_ns_per_op
			$results = $results.append({ profile, workload, median, ratio, samples: $samples })
			baseline_change = match reviewed {
				None => ""
				Some(previous) => {
					row = match previous.rows.keep_if(|r| r.profile == profile and r.workload == workload) {
						[one] => one
						_ => return Err(InvalidRocBaselineRow(profile, workload))
					}
					limits = BenchmarkTimingCache.repeat_range(row.sessions)?
					if median > limits.upper {
						$regressions = $regressions.append("${profile}/${workload}")
					}
					delta = (median / limits.median - 1) * 100
					", ${delta.to_str()}% against reviewed Roc baseline"
				}
			}
			Script.info!({ label: "roc-time", message: "${profile} ${workload}: ${median.to_str()} ns/op, ${ratio.to_str()}× ${peer.library}${baseline_change}" })?
			if ratio > 1.50 {
				$misses = $misses.append("${profile}/${workload}")
			}
		}
	}
	after = timing_control!({ binary, cwd: root, logs: work, label: "control-after" })?
	if identity != timing_identity!(options)? {
		return Err(InconclusiveReferenceEnvironment)
	}
	report = {
		identity,
		compiler,
		binary_sha256: BenchmarkEvidence.hash!(binary)?,
		source_revision: Script.command("git").output!(["rev-parse", "HEAD"])?,
		results: $results,
		controls: [before, after],
		peer_baseline_sha256: BenchmarkEvidence.hash!(baseline)?,
		possible_regressions: $regressions,
	}
	stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%SZ"])?
	destination = Path.join(work, "results-${stamp}.json")
	Path.write_utf8!(destination, Json.to_str_try(report)?)?
	Script.info!({ label: "EVIDENCE", message: Path.display(destination) })?
	admit_control(after, reviewed)?
	if !$regressions.is_empty() {
		Script.info!({ label: "REVIEW", message: "Repeat to confirm timing regressions in ${Str.join_with($regressions, ", ")}." })?
	}
	if ($misses.is_empty()) Ok({}) else Err(CompetitiveTargetsMissed($misses))
}

review_roc! : List(Str) => Try({}, _)
review_roc! = |paths| {
	if paths.len() < 3 or paths.len() > 10 or paths.any(|name| paths.keep_if(|other| other == name).len() != 1) {
		return Err(IndependentSessionsRequired)
	}
	reports : List(BenchmarkTimingCache.RocReport)
	reports = paths.map_try!(|path| Json.parse(Path.read_utf8!(Path.utf8(path))?))?
	baseline = BenchmarkTimingCache.review(reports)?
	candidate = Path.utf8(".roc-time-tmp/benchmark-replay/roc-baseline-candidate.json")
	Path.write_utf8!(candidate, "${Json.to_str_try(baseline)?}\n")?
	Script.info!({ label: "REVIEW", message: Path.display(candidate) })
}

admit_control : F64, [None, Some(BenchmarkTimingCache.RocBaseline)] -> Try({}, _)
admit_control = |measurement, reference| match reference {
	None => Ok({})
	Some(previous) => {
		limits = BenchmarkTimingCache.repeat_range(previous.controls)?
		if measurement < limits.lower or measurement > limits.upper {
			Err(InconclusiveTimingControl({ ns_per_op: measurement, lower: limits.lower, upper: limits.upper }))
		} else {
			Ok({})
		}
	}
}

timing_control! : { binary : Path, cwd : Path, logs : Path, label : Str } => Try(F64, _)
timing_control! = |{ binary, cwd, logs, label }| {
	output = BenchmarkProcess.run!({
		args: [Path.display(binary), "timing_control", "200000", "3", "9"],
		cwd,
		logs,
		label,
		environment: [],
		timeout_ms: 30000,
	})?
	elapsed = BenchmarkOptions.samples(output.stdout, 9, 500000)?
	BenchmarkOptions.median(elapsed).map_ok(|ns| ns / 200000)
}

replay_dates! : List((Str, Str)), [Timing, Fixture] => Try({}, _)
replay_dates! = |profiles, allocator| {
	BenchmarkOptions.controls(Path.read_utf8!("tests/benchmark_controls/timing-positive.txt")?)?
	root = Path.absolute!(".")?
	work = Path.absolute!(".roc-time-tmp/benchmark-replay")?
	Path.create_all!(work)?
	options = BenchmarkOptions.parse(["--smoke"])?
	expectation_controls!(work, profiles.first()?)?
	peer_cache_controls!(work)?
	references = profiles.map_try!(
		|(profile, corpus)| {
			reference = BenchmarkExpectations.load!({ profile, corpus: Path.utf8(corpus), iterations: options.iterations })?
			Ok({ profile, reference })
		},
	)?
	{ binary, version, target } = ChronoBenchmark.build_roc!({ options, root, work, allocator, source: "benchmarks/chrono/main.roc" })?
	for { profile, reference } in references {
		inputs = reference.cases.map(|case| case.text)
		expected = Str.join_with(
			reference.cases.map(
				|case| {
					text = if (profile == "seconds") case.text else case.canonical
					"${case.day.to_str()}|${case.microseconds.to_str()}|${text}\n"
				},
			),
			"",
		)
		output = BenchmarkProcess.run!({
			args: [Path.display(binary), "verify", "1", "0", "0"].concat(inputs),
			cwd: root,
			logs: work,
			label: "${profile}-verify",
			environment: [],
			timeout_ms: 30000,
		})?
		if output.stdout != expected {
			return Err(ComparisonOracleMismatch(profile, "roc-time"))
		}
		modes = BenchmarkOptions.modes.keep_if(|mode| profile == "microseconds" or !["format", "end_to_end"].contains(mode))
		for mode in modes {
			output_sample = BenchmarkProcess.run!({
				args: [Path.display(binary), mode, options.iterations.to_str(), "0", "1"].concat(inputs),
				cwd: root,
				logs: work,
				label: "${profile}-${mode}-replay",
				environment: [],
				timeout_ms: 30000,
			})?
			_ = BenchmarkOptions.samples(output_sample.stdout, 1, reference.checksums.get(mode)?)?
		}
		Script.info!({ label: "PASS", message: "${profile} cached correctness replay with ${version} (${target})" })?
	}
	Ok({})
}

peer_cache_controls! : Path => Try({}, _)
peer_cache_controls! = |work| {
	fixture = Path.join(work, "peer-controls")
	Path.create_all!(fixture)?
	digest = Path.join(fixture, "test.sha256")
	absent = Path.join(fixture, "absent.json")
	match BenchmarkEvidence.load_peer_baseline!({ baseline: absent, digest }) {
		Err(MissingPeerBaseline(_)) => {}
		_ => return Err(ExpectedMissingPeerBaseline)
	}
	baseline = Path.join(fixture, "test.json")
	Path.write_utf8!(baseline, "{}\n")?
	Path.write_utf8!(digest, "wrong-digest\n")?
	match BenchmarkEvidence.load_peer_baseline!({ baseline, digest }) {
		Err(PeerBaselineDigestMismatch) => Ok({})
		_ => Err(ExpectedPeerBaselineRejection)
	}
}

expectation_controls! : Path, (Str, Str) => Try({}, _)
expectation_controls! = |work, (profile, corpus)| {
	reviewed = Path.utf8("benchmarks/comparison/expectations")
	fixture = Path.join(work, "expectation-controls")
	Path.create_all!(fixture)?
	Path.copy!(Path.join(reviewed, "manifest.json"), Path.join(fixture, "manifest.json"))?
	bad_profile = { directory: fixture, profile: "other", corpus: Path.utf8(corpus), iterations: 1 }
	match BenchmarkExpectations.load_from!(bad_profile) {
		Err(UnknownExpectationProfile("other")) => {}
		_ => return Err(ExpectedProfileRejection)
	}
	absent = Path.join(fixture, "absent.jsonl")
	input = { ..bad_profile, profile, corpus: absent }
	match BenchmarkExpectations.load_from!(input) {
		Err(MissingExpectations(_)) => {}
		_ => return Err(ExpectedMissingEntry)
	}
	Path.write_utf8!(Path.join(fixture, "${profile}.json"), "{}\n")?
	match BenchmarkExpectations.load_from!({ ..input, corpus: Path.utf8(corpus) }) {
		Err(ExpectationDigestMismatch(_)) => Ok({})
		_ => Err(ExpectedDigestRejection)
	}
}

refresh_expectations! : List((Str, Str)) => Try({}, _)
refresh_expectations! = |profiles| {
	python = Script.env_str!("PYTHON") ?? "python3"
	if Script.command(OsStr.from_str(python)).output!(["--version"])? != "Python 3.14.3" {
		return Err(ExpectationOracleVersion("3.14.3"))
	}
	root = Path.absolute!(".")?
	work = Path.absolute!(".roc-time-tmp/benchmark-expectations-candidate")?
	Path.create_all!(work)?
	var $identities = Dict.empty()
	for (profile, corpus) in profiles {
		candidate = BenchmarkProcess.run!({
			args: [python, BenchmarkExpectations.generator, corpus, "--per-case"],
			cwd: root,
			logs: work,
			label: "${profile}-generate",
			environment: [],
			timeout_ms: 30000,
		})?
		file = Path.join(work, "${profile}.json")
		Path.write_utf8!(file, candidate.stdout)?
		$identities = $identities.insert(
			profile,
			{
				corpus_sha256: BenchmarkExpectations.hash!(Path.utf8(corpus))?,
				checksums_sha256: BenchmarkExpectations.hash!(file)?,
			},
		)
	}
	manifest = {
		schema: BenchmarkExpectations.schema,
		oracle: BenchmarkExpectations.oracle,
		generator_sha256: BenchmarkExpectations.hash!(Path.utf8(BenchmarkExpectations.generator))?,
		profiles: $identities,
	}
	Path.write_utf8!(Path.join(work, "manifest.json"), "${Json.to_str_try(manifest)?}\n")?
	for (profile, corpus) in profiles {
		_ = BenchmarkExpectations.load_from!({ directory: work, profile, corpus: Path.utf8(corpus), iterations: 1 })?
	}
	Script.info!({ label: "REVIEW", message: "Compare ${Path.display(work)} with benchmarks/comparison/expectations before accepting changes." })
}

execute! : ComparisonBenchmark.Context,
{
	name : Str,
	mode : Str,
	iterations : U64,
	warmups : U64,
	samples : U64,
	cases : List(ChronoBenchmark.Case),
	label : Str,
} => Try(BenchmarkProcess.Output, _)
execute! = |context, { name, mode, iterations, warmups, samples, cases, label }| {
	command = ComparisonBenchmark.command(
		context,
		{
			library: name,
			args: [mode, iterations.to_str(), warmups.to_str(), samples.to_str()].concat(cases.map(|case| case.text)),
		},
	)?
	BenchmarkProcess.run!({
		args: command,
		cwd: context.root,
		logs: context.work,
		label,
		environment: context.environment,
		timeout_ms: 300000,
	})
}
