## Admission for a reviewed peer timing summary. Raw samples are retained by
## the refresh report. Median values use nanoseconds per operation.
BenchmarkTimingCache := [].{
	Identity : {
		protocol : Str,
		host : Dict(Str, Str),
		input_sha256 : Dict(Str, Str),
		iterations : U64,
		warmups : U64,
		samples : U64,
		rounds : U64,
	}
	Row : { profile : Str, workload : Str, library : Str, median_ns_per_op : F64 }
	Cache : { identity : Identity, rows : List(Row), versions : Dict(Str, Str), binaries : Dict(Str, Str) }
	RocRow : { profile : Str, workload : Str, sessions : List(F64) }
	RocBaseline : { identity : Identity, compiler : Str, rows : List(RocRow), controls : List(F64) }
	RocMeasurement : { profile : Str, workload : Str, median : F64 }
	RocReport : {
		identity : Identity,
		compiler : Str,
		binary_sha256 : Str,
		source_revision : Str,
		results : List(RocMeasurement),
		controls : List(F64),
		peer_baseline_sha256 : Str,
	}

	review : List(RocReport) -> Try(RocBaseline, [InvalidRepeatability])
	review = |reports| {
		first = reports.first().map_err(|_| InvalidRepeatability)?
		if reports.len() < 3 or first.results.is_empty() or !reports.all(|item| item.identity == first.identity and item.compiler == first.compiler and item.binary_sha256 == first.binary_sha256 and item.peer_baseline_sha256 == first.peer_baseline_sha256 and item.controls.len() == 2 and item.results.len() == first.results.len()) {
			return Err(InvalidRepeatability)
		}
		controls = reports.fold([], |values, session| values.concat(session.controls))
		_ = repeat_range(controls)?
		rows = first.results.map_try(
			|{ profile, workload, .. }| {
				sessions = reports.map_try(
					|report| {
						match report.results.keep_if(|row| row.profile == profile and row.workload == workload) {
							[{ median, .. }] => Ok(median)
							_ => Err(InvalidRepeatability)
						}
					},
				)?
				_ = repeat_range(sessions)?
				Ok({ profile, workload, sessions })
			},
		)?
		Ok({ identity: first.identity, compiler: first.compiler, rows, controls })
	}

	## Extend the observed range by one between-session spread on either side.
	## Use the middle observation as the baseline for three session medians.
	repeat_range : List(F64) -> Try({ lower : F64, upper : F64, median : F64 }, [InvalidRepeatability])
	repeat_range = |observations| {
		if observations.len() < 3 or !observations.all(valid_time) {
			return Err(InvalidRepeatability)
		}
		ordered = observations.sort_with(|left, right| if (left < right) Before else if (left > right) After else Same)
		low = ordered.first().map_err(|_| InvalidRepeatability)?
		high = ordered.last().map_err(|_| InvalidRepeatability)?
		left = ordered.get((ordered.len() - 1) // 2).map_err(|_| InvalidRepeatability)?
		right = ordered.get(ordered.len() // 2).map_err(|_| InvalidRepeatability)?
		spread = high - low
		Ok({ lower: low - spread, upper: high + spread, median: (left + right) / 2 })
	}

	admit : Cache, Identity, List({ profile : Str, workload : Str, library : Str }) -> Try({}, [TimingCacheIdentity, TimingCacheRows])
	admit = |cache, expected, required| {
		if cache.identity != expected {
			return Err(TimingCacheIdentity)
		}
		if cache.rows.len() != required.len() or !required.all(
			|row| {
				matches = cache.rows.keep_if(|candidate| candidate.profile == row.profile and candidate.workload == row.workload and candidate.library == row.library)
				match matches {
					[{ median_ns_per_op, .. }] => valid_time(median_ns_per_op)
					_ => False
				}
			},
		) {
			return Err(TimingCacheRows)
		}
		Ok({})
	}

	fastest : Cache, { profile : Str, workload : Str } -> Try(Row, [NoEligiblePeer])
	fastest = |cache, { profile, workload }| {
		matching = cache.rows.keep_if(|row| row.profile == profile and row.workload == workload)
		first = matching.first().map_err(|_| NoEligiblePeer)?
		Ok(matching.fold(first, |best, candidate| if (candidate.median_ns_per_op < best.median_ns_per_op) candidate else best))
	}
}

valid_time : F64 -> Bool
valid_time = |value| value > 0 and value <= 1000000000000

test_identity : BenchmarkTimingCache.Identity
test_identity = {
	protocol: "test-v1",
	host: Dict.from_list([("arch", "arm64")]),
	input_sha256: Dict.empty(),
	iterations: 1000,
	warmups: 1,
	samples: 3,
	rounds: 2,
}

test_row = { profile: "microseconds", workload: "parse", library: "chrono" }

test_cache : BenchmarkTimingCache.Cache
test_cache = {
	identity: test_identity,
	rows: [{ profile: test_row.profile, workload: test_row.workload, library: test_row.library, median_ns_per_op: 1000 }],
	versions: Dict.empty(),
	binaries: Dict.empty(),
}

expect BenchmarkTimingCache.admit(test_cache, test_identity, [test_row]) == Ok({})
expect BenchmarkTimingCache.admit(test_cache, { ..test_identity, host: Dict.from_list([("arch", "x64")]) }, [test_row]) == Err(TimingCacheIdentity)
expect BenchmarkTimingCache.admit(test_cache, test_identity, [{ ..test_row, profile: "seconds" }]) == Err(TimingCacheRows)
expect BenchmarkTimingCache.admit({ ..test_cache, rows: [{ profile: test_row.profile, workload: test_row.workload, library: test_row.library, median_ns_per_op: 0 }] }, test_identity, [test_row]) == Err(TimingCacheRows)
expect BenchmarkTimingCache.admit({ ..test_cache, rows: [] }, test_identity, [test_row]) == Err(TimingCacheRows)
expect BenchmarkTimingCache.repeat_range([10, 14, 12]) == Ok({ lower: 6, upper: 18, median: 12 })
expect BenchmarkTimingCache.repeat_range([10, 0, 14]) == Err(InvalidRepeatability)
expect BenchmarkTimingCache.repeat_range([10, 14]) == Err(InvalidRepeatability)
