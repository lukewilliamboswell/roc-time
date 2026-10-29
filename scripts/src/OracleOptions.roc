## Explicit offline replay selection and narrow source-root adaptation. Only
## external package/platform roots move; fixture-relative imports stay intact.
OracleOptions := [].{
	names = ["gregorian", "julian", "zones", "calendar_pattern", "rfc_date", "rfc_timed"]
	Options : { names : List(Str), workers : U64 }
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 64 {
			return Err(Arguments)
		}
		parse_loop(args, { names, workers: 4 })
	}
	rewrite : { source : Str, core_path : Str, host_path : Str } -> Str
	rewrite = |{ source, core_path, host_path }| Str.join_with(
		source.split_on("\"").map_with_index(
			|part, index| {
				if (U64.rem_by(index, 2) == 0) part else if (is_external_source(part, "package/main.roc")) core_path else if (is_external_source(part, "platform/main.roc")) host_path else part
			},
		),
		"\"",
	)
}

parse_loop : List(Str), OracleOptions.Options -> Try(OracleOptions.Options, [Arguments])
parse_loop = |args, options| match args {
	[] => Ok(options)
	["--workers", text, .. as rest] => {
		workers = U64.from_str(text).map_err(|_| Arguments)?
		if workers < 1 or workers > 16 {
			return Err(Arguments)
		}
		parse_loop(rest, { ..options, workers })
	}
	["--oracle", name, .. as rest] if OracleOptions.names.contains(name) => parse_loop(rest, { ..options, names: [name] })
	_ => Err(Arguments)
}

is_external_source : Str, Str -> Bool
is_external_source = |text, suffix| text.ends_with(suffix) and {
	prefix = text.drop_suffix(suffix)
	!prefix.is_empty() and prefix.split_on("../").all(Str.is_empty)
}

## Require at least one replay worker.
expect OracleOptions.parse(["--workers", "0"]) == Err(Arguments)

## Bound the replay worker pool.
expect OracleOptions.parse(["--workers", "17"]) == Err(Arguments)

## Reject an unknown oracle profile.
expect OracleOptions.parse(["--oracle", "unknown"]) == Err(Arguments)

## Preserve the selected profile and worker budget.
expect OracleOptions.parse(["--oracle", "zones", "--workers", "3"]) == Ok({ names: ["zones"], workers: 3 })

## Rewrite only external fixture dependencies.
expect OracleOptions.rewrite({
	source: "pf: platform \"../../platform/main.roc\", fixture: \"../fixture.roc\", time: \"../../../package/main.roc\"",
	core_path: "../core/main.roc",
	host_path: "../host/main.roc",
}) == "pf: platform \"../host/main.roc\", fixture: \"../fixture.roc\", time: \"../core/main.roc\""

## Preserve unrelated and local dependency paths.
expect OracleOptions.rewrite({
	source: "\"other/package/main.roc\" \"package/main.roc\"",
	core_path: "core",
	host_path: "host",
}) == "\"other/package/main.roc\" \"package/main.roc\""
