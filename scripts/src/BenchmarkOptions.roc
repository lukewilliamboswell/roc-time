## Bounded in-process workload selection. Smoke runs validate the harness and
## checksums, not comparative performance; profile runs retain their own mode.
BenchmarkOptions := [].{
	modes = [
		"date_control",
		"date_to_day",
		"construct",
		"roundtrip",
		"add_days",
		"parse",
		"resolve",
		"format",
		"end_to_end",
		"parse_only",
	]
	Options : {
		fetch : Bool,
		smoke : Bool,
		iterations : U64,
		warmups : U64,
		samples : U64,
		roc_opt : Str,
		debug : Bool,
		profile : Str,
		argv0 : Str,
	}
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 128 {
			return Err(Arguments)
		}
		raw = parse_loop(
			args,
			{
				fetch: Bool.False,
				smoke: Bool.False,
				iterations: 100000,
				warmups: 3,
				samples: 9,
				roc_opt: "speed",
				debug: Bool.False,
				profile: "",
				argv0: "benchmark",
			},
		)?
		options = if (raw.smoke) { ..raw, iterations: 1000, warmups: 1, samples: 3 } else raw
		if options.iterations < 1 or options.iterations > 10000000 or options.samples < 1 or options.samples > 50 or options.warmups > 10 or (options.debug and options.profile.is_empty()) or (options.roc_opt != "speed" and !options.smoke and options.profile.is_empty()) {
			return Err(Arguments)
		}
		Ok(options)
	}
	controls : Str -> Try({}, [TimingRecords])
	controls = |positive| {
		for bad in ["10,2\n", "10,1\nextra\n", "bad\n", "10,1\n\n", "\n10,1\n", "0,1\n", "-1,1\n", ""] {
			if samples(bad, 1, 1) != Err(TimingRecords) {
				return Err(TimingRecords)
			}
		}
		match samples(positive, 1, 1) {
			Ok([10]) => {}
			_ => return Err(TimingRecords)
		}
		Ok({})
	}

	samples : Str, U64, U64 -> Try(List(U64), [TimingRecords])
	samples = |source, count, expected| {
		lines = source.drop_suffix("\n").split_on("\n")
		if lines.len() != count or count == 0 {
			return Err(TimingRecords)
		}
		lines.map_try(
			|line| match line.split_on(",") {
				[elapsed, checksum] => {
					nanos = U64.from_str(elapsed).map_err(|_| TimingRecords)?
					actual = U64.from_str(checksum).map_err(|_| TimingRecords)?
					if nanos == 0 or actual != expected {
						return Err(TimingRecords)
					}
					Ok(nanos)
				}
				_ => Err(TimingRecords)
			},
		)
	}
	median : List(U64) -> Try(F64, [NoSamples])
	median = |values| {
		if values.is_empty() {
			return Err(NoSamples)
		}
		sorted = values.sort()
		mid = sorted.len() // 2
		upper = sorted.get(mid).map_err(|_| NoSamples)?.to_f64()
		if (U64.rem_by(sorted.len(), 2) == 1) Ok(upper) else Ok((sorted.get(mid - 1).map_err(|_| NoSamples)?.to_f64() + upper) / 2)
	}
}

parse_loop : List(Str), BenchmarkOptions.Options -> Try(BenchmarkOptions.Options, [Arguments])
parse_loop = |args, options| match args {
	[] => Ok(options)
	["--fetch", .. as rest] => parse_loop(rest, { ..options, fetch: Bool.True })
	["--smoke", .. as rest] => parse_loop(rest, { ..options, smoke: Bool.True })
	["--debug", .. as rest] => parse_loop(rest, { ..options, debug: Bool.True })
	["--iterations", number, .. as rest] => parse_loop(rest, { ..options, iterations: U64.from_str(number).map_err(|_| Arguments)? })
	["--warmups", number, .. as rest] => parse_loop(rest, { ..options, warmups: U64.from_str(number).map_err(|_| Arguments)? })
	["--samples", number, .. as rest] => parse_loop(rest, { ..options, samples: U64.from_str(number).map_err(|_| Arguments)? })
	["--roc-opt", roc_opt, .. as rest] if ["dev", "speed"].contains(roc_opt) => parse_loop(rest, { ..options, roc_opt })
	["--profile", profile, .. as rest] if BenchmarkOptions.modes.contains(profile) => parse_loop(rest, { ..options, profile })
	["--argv0", argv0, .. as rest] => parse_loop(rest, { ..options, argv0 })
	_ => Err(Arguments)
}

## Require a profiling workload when debug symbols are requested.
expect BenchmarkOptions.parse(["--debug"]) == Err(Arguments)

## Require speed builds for comparative measurements.
expect BenchmarkOptions.parse(["--roc-opt", "dev"]) == Err(Arguments)

## Keep a bounded development smoke workload.
expect BenchmarkOptions.parse(["--smoke", "--roc-opt", "dev"]).map_ok(|options| (options.iterations, options.warmups, options.samples)) == Ok((1000, 1, 3))

## Reject malformed timing records and incorrect checksums.
expect ["10,2\n", "10,1\nextra\n", "bad\n", "10,1\n\n", "\n10,1\n", "0,1\n", "-1,1\n", ""].all(|bad| BenchmarkOptions.samples(bad, 1, 1) == Err(TimingRecords))

## Accept a positive timing record with its expected checksum.
expect BenchmarkOptions.samples("10,1\n", 1, 1) == Ok([10])

## Calculate the median independently of input order.
expect BenchmarkOptions.median([3, 1, 2]) == Ok(2)

## Avoid overflow for an even median near U64 maximum.
expect BenchmarkOptions.median([18446744073709551615, 18446744073709551614]).is_ok()
