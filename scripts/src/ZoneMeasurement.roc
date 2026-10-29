## Finite build samples, with distinct smoke regression and historical
## measurement modes. Historical providers retain observations without the
## current provider's allocation assertions.
ZoneMeasurement := [].{
	Options : { directories : List(Str), samples : U64, optimize : Str, smoke : Bool }
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 128 {
			return Err(Arguments)
		}
		found = parse_loop(args, { directories: [], samples: 3, optimize: "dev", smoke: Bool.False })?
		options = if found.smoke {
			{ ..found, samples: 1, directories: if (found.directories.is_empty()) ["tzdb/package"] else found.directories }
		} else found
		if options.directories.is_empty() or options.directories.len() > 16 or options.samples < 1 or options.samples > 10 {
			return Err(Arguments)
		}
		Ok(options)
	}
	source : Str, Str, Str, Bool, Bool -> Try(Str, [FixtureTemplate])
	source = |original, host, package_directory, static, smoke| {
		if original.split_on("\"../../platform/main.roc\"").len() != 2 or original.split_on("\"../../../tzdb/package/main.roc\"").len() != 2 {
			return Err(FixtureTemplate)
		}
		asserted = if (smoke) original else Str.join_with(original.split_on("\n").keep_if(|line| !line.contains("Host.assert!")), "\n")
		rewritten = replace(replace(asserted, "\"../../platform/main.roc\"", Json.to_str(host)), "\"../../../tzdb/package/main.roc\"", Json.to_str(package_directory))
		if static {
			if rewritten.split_on("args.get(1) ?? \"Australia/Melbourne\"").len() != 2 or rewritten.split_on("|args|").len() != 2 {
				return Err(FixtureTemplate)
			}
			Ok(replace(replace(rewritten, "|args|", "|_args|"), "args.get(1) ?? \"Australia/Melbourne\"", "\"Australia/Melbourne\""))
		} else Ok(rewritten)
	}

	peak_rss : Str -> Try(Try(U64, [Null]), [MalformedRss])
	peak_rss = |stderr| match stderr.split_on("\n").keep_if(|line| line.contains("maximum resident set size")) {
		[] => Ok(Err(Null))
		[line] => Ok(Ok(U64.from_str(line.trim().split_on(" ").first().map_err(|_| MalformedRss)?).map_err(|_| MalformedRss)?))
		_ => Err(MalformedRss)
	}

}

parse_loop = |args, options| match args {
	[] => Ok(options)
	["--smoke", .. as rest] => parse_loop(rest, { ..options, smoke: Bool.True })
	["--package", package_directory, .. as rest] if !package_directory.starts_with("--") => parse_loop(rest, { ..options, directories: options.directories.append(package_directory) })
	["--samples", text, .. as rest] => parse_loop(rest, { ..options, samples: U64.from_str(text).map_err(|_| Arguments)? })
	["--opt", optimize, .. as rest] if ["dev", "speed"].contains(optimize) => parse_loop(rest, { ..options, optimize })
	_ => Err(Arguments)
}
expect ZoneMeasurement.parse([]) == Err(Arguments)
expect ZoneMeasurement.parse(["--package", "old", "--samples", "11"]) == Err(Arguments)
expect ZoneMeasurement.parse(["--smoke"]).map_ok(|o| (o.directories, o.samples, o.smoke)) == Ok((["tzdb/package"], 1, Bool.True))
expect ZoneMeasurement.parse(["--package", "old", "--package", "current", "--opt", "speed"]).map_ok(|o| o.directories) == Ok(["old", "current"])
expect ZoneMeasurement.source("no declared imports", "host", "db", Bool.True, Bool.True) == Err(FixtureTemplate)

replace = |text, from, to| Str.join_with(text.split_on(from), to)

expect ZoneMeasurement.peak_rss("compiler output") == Ok(Err(Null))
expect ZoneMeasurement.peak_rss("  123 maximum resident set size\n") == Ok(Ok(123))
expect ZoneMeasurement.peak_rss(" wrong maximum resident set size\n") == Err(MalformedRss)
