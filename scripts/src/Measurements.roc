## Bounded process timing options and ordinary sample statistics. The checksum
## sums the generated input fields; it does not implement calendar conversion.
Measurements := [].{
	Options : { iterations : U64, runs : U64, warmups : U64, smoke : Bool }
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 64 {
			return Err(Arguments)
		}
		found = parse_loop(args, { iterations: 1000000, runs: 15, warmups: 3, smoke: Bool.False })?
		options = if found.smoke {
			{ ..found, iterations: 1000, runs: 2, warmups: 0 }
		} else found
		if options.iterations < 1 or options.iterations > 100000000 or options.runs < 2 or options.runs > 10000 or options.warmups > 10000 {
			return Err(Arguments)
		}
		Ok(options)
	}
	checksum : U64 -> U64
	checksum = |count| {
		var $sum = 0.U64
		for i in (0.U64).until(count) {
			$sum = $sum + 1970 + U64.rem_by(i * 37, 8030) + U64.rem_by(i * 17, 12) + 1 + U64.rem_by(i * 13, 28) + 1
		}
		$sum
	}
	statistics : List(F64) -> Try({ mean_seconds : F64, stdev_seconds : F64 }, [TooFewSamples])
	statistics = |samples| {
		if samples.len() < 2 {
			return Err(TooFewSamples)
		}
		mean_seconds = samples.fold(0.F64, |sum, n| sum + n) / samples.len().to_f64()
		variance = samples.fold(0.F64, |sum, n| sum + (n - mean_seconds) * (n - mean_seconds)) / (samples.len() - 1).to_f64()
		Ok({ mean_seconds, stdev_seconds: F64.sqrt(variance) })
	}
}

parse_loop = |args, found| match args {
	[] => Ok(found)
	["--smoke", .. as rest] => parse_loop(rest, { ..found, smoke: Bool.True })
	["--iterations", text, .. as rest] => parse_loop(rest, { ..found, iterations: U64.from_str(text).map_err(|_| Arguments)? })
	["--runs", text, .. as rest] => parse_loop(rest, { ..found, runs: U64.from_str(text).map_err(|_| Arguments)? })
	["--warmups", text, .. as rest] => parse_loop(rest, { ..found, warmups: U64.from_str(text).map_err(|_| Arguments)? })
	_ => Err(Arguments)
}
expect Measurements.parse(["--runs", "1"]) == Err(Arguments)
expect Measurements.parse(["--warmups", "18446744073709551615"]) == Err(Arguments)
expect Measurements.parse(["--iterations", "100000001"]) == Err(Arguments)
expect Measurements.checksum(0) == 0
expect Measurements.checksum(1) == 1972
expect Measurements.statistics([1, 2, 3, 4, 5]) == Ok({ mean_seconds: 3, stdev_seconds: F64.sqrt(2.5) })
expect Measurements.statistics([2, 2]) == Ok({ mean_seconds: 2, stdev_seconds: 0 })
expect Measurements.statistics([1]) == Err(TooFewSamples)

# 337260 is the common period of 8030, 12 and 28. The multipliers
# are coprime to their moduli, so each residue occurs equally often:
# sum = period * (1970 + 8029/2 + 13/2 + 29/2).
expect Measurements.checksum(337260) == 2025414930
