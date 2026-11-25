## Finite invocation budgets and compiler arguments for temporal fuzzing.
FuzzOptions := [].{
	Operation : [Build, Accept, Replay, Run, Lifecycle, All]
	Options : { operation : Operation, names : List(Str), runs : U64, seconds : U64, seed : U64 }
	names : List(Str)
	names = [
		"precision",
		"spans",
		"coverage",
		"retention",
		"gregorian",
		"arithmetic",
		"calendars",
		"clock",
		"nano_clock",
		"offsets",
		"nano_local",
		"zones",
		"events",
		"nano_posix",
		"patterns",
		"recurrence",
		"descriptions",
		"interchange",
	]

	## Deterministic Model and Solve roots use the same platform pin.
	spec_roots : List(Str)
	spec_roots = [
		"spec_precision",
		"spec_coverage",
		"spec_recurrence",
		"spec_nano_local",
		"spec_zone_selection",
		"spec_calendar_evidence",
		"spec_timed_cursor",
		"spec_zone_classification",
	]

	## Properties keep independent corpus/baseline identities inside three builds.
	suite : Str -> Str
	suite = |name| match name {
		"precision" | "spans" | "coverage" | "retention" | "events" | "nano_posix" => "core_suite"
		"gregorian" | "arithmetic" | "calendars" | "clock" | "nano_clock" | "offsets" | "nano_local" => "civil_suite"
		"zones" | "patterns" | "recurrence" | "descriptions" | "interchange" => "interpretation_suite"
		_ => name
	}

	member : Str -> Str
	member = |name| match name {
		"coverage" => "coverage-v2"
		"nano_clock" => "nano-clock-v1"
		"nano_posix" => "nano-posix-v1"
		"nano_local" => "nano-local-v1"
		_ => "${name}-v1"
	}

	selection : Str -> List(Str)
	selection = |name| if (names.contains(name)) ["--target=${member(name)}"] else []

	builds : List(Str) -> List(Str)
	builds = |selected| selected.map(suite).fold([], |found, name| if (found.contains(name)) found else found.append(name))

	## Compile each measured executable independently of earlier checks/builds.
	build_args : { target : Str, source : Str, output : Str } -> List(Str)
	build_args = |{ target, source, output }| [
		"build",
		"--fuzz",
		"--opt=speed",
		"--no-cache",
		"--target=${target}",
		source,
		"--output=${output}",
	]

	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 512 {
			return Err(Arguments)
		}
		parse_loop(args, { operation: All, names, runs: 10000, seconds: 5, seed: 1 })
	}
}

## Selecting several members never duplicates a compiler invocation, and the
## coverage regression keeps its existing v2 binary encoding/report identity.
expect FuzzOptions.builds(["coverage", "precision", "clock", "offsets", "recurrence"]) == ["core_suite", "civil_suite", "interpretation_suite"]
expect FuzzOptions.selection("coverage") == ["--target=coverage-v2"]
expect FuzzOptions.selection("nano_clock") == ["--target=nano-clock-v1"]
expect FuzzOptions.selection("lifecycle") == []

## The executed compiler argv must enforce the reviewed measurement policy.
## Paths remain single argv values, including when they contain spaces.
expect {
	FuzzOptions.build_args({
		target: "x64musl",
		source: "tests/interpretation_suite/main.roc",
		output: "/tmp/time profiles/recurrence",
	}) == [
		"build",
		"--fuzz",
		"--opt=speed",
		"--no-cache",
		"--target=x64musl",
		"tests/interpretation_suite/main.roc",
		"--output=/tmp/time profiles/recurrence",
	] and FuzzOptions.build_args({
		target: "arm64mac",
		source: "tests/civil_suite/main.roc",
		output: "/tmp/clock",
	}).contains("--target=arm64mac")
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
