## Explicit comparison bounds, rotation and Linux affinity admission. No
## subject timing or expected temporal value is synthesized by these helpers.
ComparisonOptions := [].{
	Options : { fetch : Bool, smoke : Bool, iterations : U64, warmups : U64, samples : U64, rounds : U64, profile : Str, cpu : List(U64) }
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 128 {
			return Err(Arguments)
		}
		raw = parse_loop(args, { fetch: Bool.False, smoke: Bool.False, iterations: 100000, warmups: 3, samples: 9, rounds: 3, profile: "both", cpu: [] })?
		options = if (raw.smoke) { ..raw, iterations: 1000, warmups: 1, samples: 3, rounds: 1 } else raw
		if options.iterations < 1 or options.iterations > 10000000 or options.warmups > 10 or options.samples < 1 or options.samples > 50 or options.rounds < 1 or options.rounds > 10 {
			return Err(Arguments)
		}
		Ok(options)
	}
	affinity : Str -> Try(List(U64), [Affinity])
	affinity = |status| {
		lines = status.split_on("\n").keep_if(|line| line.starts_with("Cpus_allowed_list:"))
		text = match lines {
			[one] => one.drop_prefix("Cpus_allowed_list:").trim()
			_ => return Err(Affinity)
		}
		var $cpus = []
		for part in text.split_on(",") {
			match part.split_on("-") {
				[one] => {
					$cpus = $cpus.append(U64.from_str(one).map_err(|_| Affinity)?)
				}
				[start, end] => {
					first = U64.from_str(start).map_err(|_| Affinity)?
					last = U64.from_str(end).map_err(|_| Affinity)?
					if last < first or last > 65535 {
						return Err(Affinity)
					}
					for cpu in first.to(last) {
						$cpus = $cpus.append(cpu)
					}
				}
				_ => return Err(Affinity)
			}
		}
		if $cpus.is_empty() or $cpus.len() > 65536 {
			return Err(Affinity)
		}
		Ok($cpus)
	}
	order : List(Str), U64, U64 -> List(Str)
	order = |names, round, index| {
		if names.is_empty() {
			return []
		}
		shift = U64.rem_by(round + index, names.len())
		shifted = names.drop_first(shift).concat(names.take_first(shift))
		if (U64.rem_by(round, 2) == 0) shifted else shifted.fold([], |reversed, name| [name].concat(reversed))
	}
}

parse_loop = |args, options| match args {
	[] => Ok(options)
	["--fetch", .. as rest] => parse_loop(rest, { ..options, fetch: Bool.True })
	["--smoke", .. as rest] => parse_loop(rest, { ..options, smoke: Bool.True })
	["--iterations", value, .. as rest] => parse_loop(rest, { ..options, iterations: U64.from_str(value).map_err(|_| Arguments)? })
	["--warmups", value, .. as rest] => parse_loop(rest, { ..options, warmups: U64.from_str(value).map_err(|_| Arguments)? })
	["--samples", value, .. as rest] => parse_loop(rest, { ..options, samples: U64.from_str(value).map_err(|_| Arguments)? })
	["--rounds", value, .. as rest] => parse_loop(rest, { ..options, rounds: U64.from_str(value).map_err(|_| Arguments)? })
	["--profile", profile, .. as rest] if ["microseconds", "seconds", "both"].contains(profile) => parse_loop(rest, { ..options, profile })
	["--cpu", value, .. as rest] => parse_loop(rest, { ..options, cpu: [U64.from_str(value).map_err(|_| Arguments)?] })
	_ => Err(Arguments)
}
expect ComparisonOptions.parse(["--rounds", "0"]) == Err(Arguments)
expect ComparisonOptions.affinity("Name:\troc\nCpus_allowed_list:\t0-2,5\n") == Ok([0, 1, 2, 5])
expect ComparisonOptions.affinity("Cpus_allowed_list:\t2-1\n") == Err(Affinity)
expect ComparisonOptions.order(["a", "b", "c"], 0, 1) == ["b", "c", "a"]
expect ComparisonOptions.order(["a", "b", "c"], 1, 0) == ["a", "c", "b"]
