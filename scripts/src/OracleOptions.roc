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
	rewrite : Str, Str, Str -> Str
	rewrite = |source, core_path, host_path| Str.join_with(
		source.split_on("\"").map_with_index(
			|part, index| {
				if (U64.rem_by(index, 2) == 0) part else if (external(part, "package/main.roc")) core_path else if (external(part, "platform/main.roc")) host_path else part
			},
		),
		"\"",
	)
}

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

external = |text, suffix| text.ends_with(suffix) and {
	prefix = text.drop_suffix(suffix)
	!prefix.is_empty() and prefix.split_on("../").all(Str.is_empty)
}
expect OracleOptions.parse(["--workers", "0"]) == Err(Arguments)
expect OracleOptions.parse(["--workers", "17"]) == Err(Arguments)
expect OracleOptions.parse(["--oracle", "unknown"]) == Err(Arguments)
expect OracleOptions.parse(["--oracle", "zones", "--workers", "3"]) == Ok({ names: ["zones"], workers: 3 })
expect OracleOptions.rewrite("pf: platform \"../../platform/main.roc\", fixture: \"../fixture.roc\", time: \"../../../package/main.roc\"", "../core/main.roc", "../host/main.roc") == "pf: platform \"../host/main.roc\", fixture: \"../fixture.roc\", time: \"../core/main.roc\""
expect OracleOptions.rewrite("\"other/package/main.roc\" \"package/main.roc\"", "core", "host") == "\"other/package/main.roc\" \"package/main.roc\""
