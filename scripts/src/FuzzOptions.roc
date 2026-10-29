## Finite command-line budgets for the one temporal fuzz runner.
FuzzOptions := [].{
	Options : { operation : Str, names : List(Str), runs : U64, seconds : U64, seed : U64 }
	names : List(Str)
	names = ["precision", "spans", "coverage", "gregorian", "arithmetic", "calendars", "clock", "offsets", "zones", "events", "patterns", "recurrence", "descriptions", "interchange"]

	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 512 {
			return Err(Arguments)
		}
		parse_loop(args, { operation: "all", names, runs: 10000, seconds: 5, seed: 1 })
	}
}

parse_loop = |args, options| match args {
	[] => if options.seconds > 18446744073709521 {
		Err(Arguments)
	} else {
		Ok(options)
	}
	["--operation", operation, .. as rest] if ["build", "accept", "replay", "run", "lifecycle", "all"].contains(operation) => parse_loop(rest, { ..options, operation })
	["--runs", value, .. as rest] => parse_loop(rest, { ..options, runs: positive(value)? })
	["--seconds", value, .. as rest] => parse_loop(rest, { ..options, seconds: positive(value)? })
	["--seed", value, .. as rest] => parse_loop(rest, { ..options, seed: positive(value)? })
	["--targets", .. as rest] => {
		(names, remaining) = take_names(rest, [])
		if names.is_empty() or !names.all(|name| FuzzOptions.names.contains(name)) {
			return Err(Arguments)
		}
		parse_loop(remaining, { ..options, names: names })
	}
	_ => Err(Arguments)
}

positive = |text| {
	number = U64.from_str(text).map_err(|_| Arguments)?
	if number == 0 {
		Err(Arguments)
	} else {
		Ok(number)
	}
}

expect FuzzOptions.parse(["--runs", "0"]) == Err(Arguments)
expect FuzzOptions.parse(["--targets", "unknown"]) == Err(Arguments)
expect FuzzOptions.parse(["--operation", "replay", "--targets", "clock", "spans", "--seed", "42"]).map_ok(|options| (options.operation, options.names, options.seed)) == Ok(("replay", ["clock", "spans"], 42))

take_names = |args, found| match args {
	[name, .. as rest] if !name.starts_with("--") => take_names(rest, found.append(name))
	_ => (found, args)
}

expect FuzzOptions.parse(["--seconds", "18446744073709551615"]) == Err(Arguments)
