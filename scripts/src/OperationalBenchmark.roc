import cli.OsStr
import cli.Path
import BenchmarkEvidence
import BenchmarkOptions
import BenchmarkProcess
import BenchmarkTimingCache
import ChronoBenchmark
import ComparisonOptions
import Script

## Operational native workloads and the separately pinned interval peer.
OperationalBenchmark := [].{
	Mode : [Replay, Measure, RefreshPeers({ fetch : Bool })]
	run! : Mode => Try({}, _)
	run! = |operation| {
		root = Path.absolute!(".")?
		work = Path.absolute!(".roc-time-tmp/benchmark-operational")?
		Path.create_all!(work)?
		options = BenchmarkOptions.parse(["--smoke"])?
		{ binary, target, version } = ChronoBenchmark.build_roc!({ options, root, work, allocator: if (operation == Replay) Fixture else Timing, source: "benchmarks/operational/main.roc" })?
		if operation == Replay {
			for request in operational_requests {
				_ = run_operational!({ binary, root, work, request, iterations: 64, samples: 1, warmups: 0, label: "replay" })?
			}
			return Script.info!({ label: "PASS", message: "${operational_requests.len().to_str()} coverage, zone and recurrence combinations checked against independent fixtures (${target})." })
		}

		host = BenchmarkEvidence.host!()?
		identity = operational_identity!(host, work)?
		roc_identity = roc_identity!(identity)?
		required = operational_requests.keep_if(competitive_coverage).map(
			|request| {
				profile: request.profile,
				workload: request.mode,
				library: "rangemap",
			},
		)
		peer : [Cached(BenchmarkTimingCache.Cache), Fresh({ binary : Path, rust_version : Str })]
		peer = match operation {
			Measure => {
				baseline = Path.utf8(".roc-time-tmp/benchmark-baselines/coverage-peer-baseline.json")
				digest = Path.utf8(".roc-time-tmp/benchmark-baselines/coverage-peer-baseline.sha256")
				if !Path.exists!(baseline)? or !Path.exists!(digest)? {
					return Err(MissingCoveragePeerBaseline("blueprint run benchmark-operations-peers"))
				}
				cache = BenchmarkEvidence.load_peer_baseline!({ baseline, digest })?
				BenchmarkTimingCache.admit(cache, identity, required)?
				Cached(cache)
			}
			RefreshPeers({ fetch }) => Fresh(build_coverage_peer!({ root, work, target, fetch })?)
			Replay => crash "replay already completed"
		}
		reviewed = load_roc_baseline!({ identity: roc_identity, compiler: version })?
		before = timing_control!({ binary, root, work, label: "before" })?
		check_control(before, reviewed)?
		var $results = []
		var $peer_rows = []
		var $misses = []
		var $regressions = []
		for (request, index) in operational_requests.map_with_index(|item, n| (item, n)) {
			competitive = competitive_coverage(request)
			var $timings = []
			var $peer_timings = []
			for round in (1.U64).to(identity.rounds) {
				subjects = match peer {
					Fresh(_) if competitive => ComparisonOptions.order({ names: ["roc-time", "rangemap"], round, index })
					_ => ["roc-time"]
				}
				var $observations = []
				for name in subjects {
					executable = match peer {
						Fresh(data) if name == "rangemap" => data.binary
						_ => binary
					}
					sampled = run_operational!({
						binary: executable,
						root,
						work,
						request,
						iterations: request.iterations,
						samples: identity.samples,
						warmups: identity.warmups,
						label: "${round.to_str()}-${name}",
					})?
					$observations = $observations.append(sampled.checksum)
					if name == "roc-time" {
						$timings = $timings.concat(sampled.timings)
					} else {
						$peer_timings = $peer_timings.concat(sampled.timings)
					}
				}
				if $observations.first()? != $observations.last()? {
					return Err(CoveragePeerOutputMismatch(request.profile, request.mode))
				}
			}
			median = BenchmarkOptions.median($timings)? / request.iterations.to_f64()
			profile_key = "${request.family}/${request.profile}"
			change = match reviewed {
				[previous] => {
					row = match previous.rows.keep_if(|item| item.profile == profile_key and item.workload == request.mode) {
						[one] => one
						_ => return Err(InvalidOperationalRocBaseline(profile_key, request.mode))
					}
					range = BenchmarkTimingCache.repeat_range(row.sessions)?
					if median > range.upper {
						$regressions = $regressions.append("${profile_key}/${request.mode}")
					}
					[(median / range.median - 1) * 100]
				}
				_ => []
			}
			ratio = if competitive {
				peer_ns = match peer {
					Cached(cache) => BenchmarkTimingCache.fastest(cache, { profile: request.profile, workload: request.mode })?.median_ns_per_op
					Fresh(_) => {
						peer_median = BenchmarkOptions.median($peer_timings)? / request.iterations.to_f64()
						$peer_rows = $peer_rows.append({ profile: request.profile, workload: request.mode, library: "rangemap", median_ns_per_op: peer_median })
						peer_median
					}
				}
				value = median / peer_ns
				if value > 1.50 {
					$misses = $misses.append("${request.profile}/${request.mode}")
				}
				[value]
			} else {
				[]
			}
			$results = $results.append({ request, timings: $timings, peer_timings: $peer_timings, median_ns_per_op: median, ratio, baseline_change_percent: change })
		}
		after = timing_control!({ binary, root, work, label: "after" })?
		check_control(after, reviewed)?
		if host != BenchmarkEvidence.host!()? {
			return Err(InconclusiveReferenceEnvironment)
		}
		peer_baseline_sha256 = match peer {
			Fresh({ binary: peer_binary, rust_version }) => {
				cache = { identity, rows: $peer_rows, versions: Dict.from_list([("rust", rust_version), ("rangemap", "1.7.1")]), binaries: Dict.from_list([("rangemap", BenchmarkEvidence.hash!(peer_binary)?)]) }
				BenchmarkTimingCache.admit(cache, identity, required)?
				candidate = Path.join(work, "coverage-peer-baseline-candidate.json")
				Path.write_utf8!(candidate, "${Json.to_str_try(cache)?}\n")?
				Script.info!({ label: "REVIEW", message: Path.display(candidate) })?
				Script.info!({ label: "SHA256", message: BenchmarkEvidence.hash!(candidate)? })?
				BenchmarkEvidence.hash!(candidate)?
			}
			Cached(_) => BenchmarkEvidence.hash!(Path.utf8(".roc-time-tmp/benchmark-baselines/coverage-peer-baseline.json"))?
		}
		files = BenchmarkEvidence.collect_sources!(Path.utf8("benchmarks/operational"), Dict.empty())?
		report = {
			scope: "coverage comparisons and absolute named-zone and recurrence timings; fixture preparation and independent verification outside the timer",
			version,
			target,
			identity,
			sources: files,
			session: {
				identity: roc_identity,
				compiler: version,
				binary_sha256: BenchmarkEvidence.hash!(binary)?,
				source_revision: Script.command("git").output!(["rev-parse", "HEAD"])?,
				peer_baseline_sha256,
				controls: [before, after],
				results: $results.map(
					|entry| {
						profile: "${entry.request.family}/${entry.request.profile}",
						workload: entry.request.mode,
						median: entry.median_ns_per_op,
					},
				),
			},
			results: $results,
			misses: $misses,
			possible_regressions: $regressions,
		}
		stamp = Script.command("date").output!(["-u", "+%Y%m%dT%H%M%SZ"])?
		path = Path.join(work, "results-${stamp}.json")
		Path.write_utf8!(path, Json.to_str_try(report)?)?
		Script.info!({ label: "EVIDENCE", message: Path.display(path) })?
		if !$regressions.is_empty() {
			Script.info!({ label: "REVIEW", message: "${$regressions.len().to_str()} possible operational timing regressions require an independent repeat." })?
		}
		if ($misses.is_empty()) Ok({}) else Err(CoverageTargetsMissed($misses))
	}

	review! : List(Str) => Try({}, _)
	review! = |paths| {
		if paths.len() < 3 or paths.len() > 10 or paths.any(|name| paths.keep_if(|other| name == other).len() != 1) {
			return Err(IndependentSessionsRequired)
		}
		reports : List({ session : BenchmarkTimingCache.RocReport })
		reports = paths.map_try!(|path| Json.parse(Path.read_utf8!(Path.utf8(path))?))?
		baseline = BenchmarkTimingCache.review(reports.map(|report| report.session))?
		destination = Path.utf8(".roc-time-tmp/benchmark-operational/roc-baseline-candidate.json")
		Path.write_utf8!(destination, "${Json.to_str_try(baseline)?}\n")?
		Script.info!({ label: "REVIEW", message: Path.display(destination) })
	}
}

roc_identity! : BenchmarkTimingCache.Identity => Try(BenchmarkTimingCache.Identity, _)
roc_identity! = |identity| {
	var $inputs = identity.input_sha256
	for path in [
		"benchmarks/operational/main.roc",
		"benchmarks/operational/ZoneWorkload.roc",
		"benchmarks/operational/RecurrenceWorkload.roc",
		"tzdb/package/manifest.json",
		"tzdb/package/names.txt",
		"tzdb/package/zones.txt",
	] {
		$inputs = $inputs.insert(path, BenchmarkEvidence.hash!(Path.utf8(path))?)
	}
	Ok({ ..identity, input_sha256: $inputs })
}

load_roc_baseline! : { identity : BenchmarkTimingCache.Identity, compiler : Str } => Try(List(BenchmarkTimingCache.RocBaseline), _)
load_roc_baseline! = |{ identity, compiler }| {
	path = Path.utf8(".roc-time-tmp/benchmark-baselines/operational-roc-baseline.json")
	if !Path.exists!(path)? {
		return Ok([])
	}
	baseline : BenchmarkTimingCache.RocBaseline
	baseline = Json.parse(Path.read_utf8!(path)?)?
	if baseline.identity != identity or baseline.compiler != compiler {
		Script.info!({ label: "BASELINE", message: "Operational Roc baseline has a different compiler or protocol identity." })?
		return Ok([])
	}
	Ok([baseline])
}

timing_control! : { binary : Path, root : Path, work : Path, label : Str } => Try(F64, _)
timing_control! = |{ binary, root, work, label }| {
	request = { family: "timing", profile: "loop", mode: "control", args: [], iterations: 10000 }
	result = run_operational!({ binary, root, work, request, iterations: request.iterations, warmups: 3, samples: 9, label })?
	if result.checksum != 15000 {
		return Err(TimingControlWrongOutput)
	}
	BenchmarkOptions.median(result.timings).map_ok(|ns| ns / request.iterations.to_f64())
}

check_control : F64, List(BenchmarkTimingCache.RocBaseline) -> Try({}, _)
check_control = |time, reviewed| match reviewed {
	[baseline] => {
		range = BenchmarkTimingCache.repeat_range(baseline.controls)?
		if time < range.lower or time > range.upper {
			Err(InconclusiveOperationalControl({ observed: time, lower: range.lower, upper: range.upper }))
		} else {
			Ok({})
		}
	}
	_ => Ok({})
}

OperationalRequest : { family : Str, profile : Str, mode : Str, args : List(Str), iterations : U64 }

operational_requests : List(OperationalRequest)
operational_requests = {
	var $rows = []
	for count in [0.U64, 8, 4096] {
		shapes = if (count == 0) ["sparse"] else ["sparse", "dense", "disjoint"]
		for shape in shapes {
			blocks = if (shape == "dense") count // 2 else count
			short_matches = U64.min(1, blocks)
			long_matches = U64.min(64, blocks)
			var $cases = ["sorted", "unsorted", "union", "intersection", "difference"].map(|mode| (mode, 0.U64))
			if count > 1 {
				$cases = $cases.append(("reject-unsorted", 0))
			}
			for name in ["contains", "fold-overlap", "materialize-overlap"] {
				$cases = $cases.append((name, 0))
				if short_matches > 0 {
					$cases = $cases.append((name, short_matches))
				}
				if long_matches > short_matches and name != "contains" {
					$cases = $cases.append((name, long_matches))
				}
			}
			for (mode, matches) in $cases {
				$rows = $rows.append({
					family: "coverage",
					profile: "${shape}-${count.to_str()}-${matches.to_str()}",
					mode,
					args: [shape, count.to_str(), matches.to_str()],
					iterations: if (count == 4096) 300 else 10000,
				})
			}
		}
	}
	for (label, zone) in [("new-york", "America/New_York"), ("lord-howe", "Australia/Lord_Howe")] {
		for mode in ["load", "reject-schema", "lookup"] {
			$rows = $rows.append({ family: "zone", profile: label, mode, args: [zone, "ordinary"], iterations: 300 })
		}
		for scenario in ["ordinary", "gap", "gap-start", "gap-end", "fold", "fold-start", "fold-end", "outside"] {
			for mode in ["offset", "resolve"] {
				$rows = $rows.append({ family: "zone", profile: "${label}-${scenario}", mode, args: [zone, scenario], iterations: 10000 })
			}
		}
	}
	for profile in ["daily", "monthly", "distant"] {
		for mode in ["construct", "invalid-count", "first", "window", "resume"] {
			$rows = $rows.append({ family: "recurrence", profile, mode, args: [profile], iterations: 1000 })
		}
	}
	$rows
}

competitive_coverage : OperationalRequest -> Bool
competitive_coverage = |request| request.family == "coverage" and request.mode != "reject-unsorted"

run_operational! : { binary : Path, root : Path, work : Path, request : OperationalRequest, iterations : U64, warmups : U64, samples : U64, label : Str } => Try({ checksum : U64, timings : List(U64) }, _)
run_operational! = |{ binary, root, work, request, iterations, samples, warmups, label: suffix }| {
	label = "${request.family}-${request.profile}-${request.mode}-${suffix}"
	command = [Path.display(binary), "${request.family}-${request.mode}"].concat(request.args).concat([
		iterations.to_str(),
		warmups.to_str(),
		samples.to_str(),
	])
	Path.write_utf8!(Path.join(work, "${label}.argv.json"), Json.to_str_try(command)?)?
	result = BenchmarkProcess.run!({ args: command, cwd: root, logs: work, label, environment: [], timeout_ms: 30000 })?
	checked = result.stdout.split_first("\n")?
	checksum = U64.from_str(checked.before)?
	timings = BenchmarkOptions.samples(checked.after, samples, checksum)?
	Ok({ checksum, timings })
}

operational_identity! : Dict(Str, Str), Path => Try(BenchmarkTimingCache.Identity, _)
operational_identity! = |host, work| {
	matrix = Path.join(work, "workloads.json")
	Path.write_utf8!(matrix, Json.to_str_try(operational_requests)?)?
	inputs = [
		("coverage-matrix", matrix),
		("coverage-fixture", Path.utf8("benchmarks/operational/CoverageWorkload.roc")),
		("coverage-adapter", Path.utf8("benchmarks/operational/rust/src/main.rs")),
		("coverage-lock", Path.utf8("benchmarks/operational/rust/Cargo.lock")),
		("coverage-manifest", Path.utf8("benchmarks/operational/rust/Cargo.toml")),
		("rust-version", Path.utf8("benchmarks/chrono/rust-version")),
	]
	hashes = inputs.map_try!(|(name, file)| Ok((name, BenchmarkEvidence.hash!(file)?)))?
	Ok({
		protocol: "coverage-half-open-v2/materialize-canonical-results/opaque-input-and-output/cargo-locked-release/rotated-monotonic",
		host,
		input_sha256: Dict.from_list(hashes),
		iterations: 0,
		warmups: 3,
		samples: 9,
		rounds: 3,
	})
}

build_coverage_peer! : { root : Path, work : Path, target : Str, fetch : Bool } => Try({ binary : Path, rust_version : Str }, _)
build_coverage_peer! = |{ root, work, target, fetch }| {
	rustc = Script.env_str!("RUSTC") ?? "rustc"
	version = Script.command(OsStr.from_str(rustc)).output!(["-Vv"])?
	pin = Path.read_utf8!("benchmarks/chrono/rust-version")?.trim()
	if !version.split_on("\n").contains("release: ${pin}") {
		return Err(CoverageRustVersion(pin))
	}
	rust_target = if (target == "arm64mac") "aarch64-apple-darwin" else "x86_64-unknown-linux-musl"
	manifest = "benchmarks/operational/rust/Cargo.toml"
	environment = [
		("RUSTC", rustc),
		("CARGO_HOME", "${Path.display(root)}/.roc-time-tmp/chrono-cargo"),
		("CARGO_TARGET_DIR", "${Path.display(work)}/rust-target"),
	]
	if fetch {
		_ = BenchmarkProcess.run!({
			args: ["cargo", "fetch", "--locked", "--manifest-path", manifest],
			cwd: root,
			logs: work,
			label: "coverage-fetch",
			environment,
			timeout_ms: 300000,
		})?
	}
	_ = BenchmarkProcess.run!({
		args: ["cargo", "build", "--offline", "--locked", "--release", "--target", rust_target, "--manifest-path", manifest],
		cwd: root,
		logs: work,
		label: "coverage-build",
		environment,
		timeout_ms: 300000,
	})?
	Ok({ binary: Path.join(work, "rust-target/${rust_target}/release/roc-time-coverage-comparator"), rust_version: version })
}
