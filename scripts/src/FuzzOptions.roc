## Finite command-line budgets for the one temporal fuzz runner.
FuzzOptions := [].{
	Operation : [Build, Accept, Replay, Run, Lifecycle, All]
	Options : { operation : Operation, names : List(Str), runs : U64, seconds : U64, seed : U64 }
	names : List(Str)
	names = [
		"precision",
		"spans",
		"coverage",
		"gregorian",
		"arithmetic",
		"calendars",
		"clock",
		"offsets",
		"zones",
		"events",
		"patterns",
		"recurrence",
		"descriptions",
		"interchange",
	]

	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 512 {
			return Err(Arguments)
		}
		parse_loop(args, { operation: All, names, runs: 10000, seconds: 5, seed: 1 })
	}
}

parse_loop : List(Str), FuzzOptions.Options -> Try(FuzzOptions.Options, [Arguments])
parse_loop = |args, options| match args {
	[] => if options.seconds > 18446744073709521 {
		Err(Arguments)
	} else {
		Ok(options)
	}
	["--operation", text, .. as rest] => {
		operation = match text {
			"build" => Build
			"accept" => Accept
			"replay" => Replay
			"run" => Run
			"lifecycle" => Lifecycle
			"all" => All
			_ => return Err(Arguments)
		}
		parse_loop(rest, { ..options, operation })
	}
	["--runs", value, .. as rest] => parse_loop(rest, { ..options, runs: parse_positive(value)? })
	["--seconds", value, .. as rest] => parse_loop(rest, { ..options, seconds: parse_positive(value)? })
	["--seed", value, .. as rest] => parse_loop(rest, { ..options, seed: parse_positive(value)? })
	["--targets", .. as rest] => {
		{ names, remaining } = take_names({
			args: rest,
			found: [],
		})
		if names.is_empty() or !names.all(|name| FuzzOptions.names.contains(name)) {
			return Err(Arguments)
		}
		parse_loop(remaining, { ..options, names: names })
	}
	_ => Err(Arguments)
}

parse_positive : Str -> Try(U64, [Arguments])
parse_positive = |text| {
	number = U64.from_str(text).map_err(|_| Arguments)?
	if number == 0 {
		Err(Arguments)
	} else {
		Ok(number)
	}
}

## Require a positive exploration run budget.
expect FuzzOptions.parse(["--runs", "0"]) == Err(Arguments)

## Reject an unknown semantic target.
expect FuzzOptions.parse(["--targets", "unknown"]) == Err(Arguments)

## Decode the requested operation, target order and seed.
expect FuzzOptions.parse(["--operation", "replay", "--targets", "clock", "spans", "--seed", "42"]).map_ok(|options| (options.operation, options.names, options.seed)) == Ok((Replay, ["clock", "spans"], 42))

take_names : { args : List(Str), found : List(Str) } -> { names : List(Str), remaining : List(Str) }
take_names = |{ args, found }| match args {
	[name, .. as rest] if !name.starts_with("--") => take_names({
		args: rest,
		found: found.append(name),
	})
	_ => { names: found, remaining: args }
}

## Bound the campaign deadline arithmetic.
expect FuzzOptions.parse(["--seconds", "18446744073709551615"]) == Err(Arguments)
