## The integration gate's execution inventory. Temporal expectations remain in
## their independent corpora and fixture assertions, not in this command list.
IntegrationCases := [].{
	Case : { name : Str, program : Str, args : List(Str) }

	all : Str, Str, Str -> List(Case)
	all = |roc, python, work| {
		py = |name, args| { name, program: python, args }
		[
			{ name: "domain and representation diagnostics", program: "scripts/check_compile_failures.roc", args: [] },
		].concat(application(roc, work, "static_dispatch", ["dev"]))
			.concat(application(roc, work, "codecs", ["dev", "speed"]))
			.concat([
				py("Chrono correctness smoke", ["scripts/benchmark_chrono.py", "--smoke", "--fetch", "--roc-opt", "dev"]),
				{ name: "parser and coverage allocation identities", program: "scripts/check_resource_identities.roc", args: [] },
				py("independent Gregorian queries", ["scripts/test_civil_queries.py"]),
				py("independent DATE export", ["scripts/test_date_export.py"]),
				py("independent timed export", ["scripts/test_timed_export.py"]),
				py("independent UTC coordinates", ["tests/utc_cancellations_checks/reference.py"]),
			])
			.concat(application(roc, work, "zoned_appointment_checks", ["dev", "speed"]))
			.concat([
				{ name: "fuzz replay and bounded search", program: "scripts/fuzz.roc", args: ["--", "--operation", "all", "--runs", "100", "--seconds", "1", "--seed", "1"] },
				py("instrumented fixture controls", ["scripts/fixture_platform.py", "--verify"]),
				py("oracle transport controls", ["scripts/test_oracle_replay.py"]),
				py("independent temporal oracles", ["scripts/oracles.py"]),
				py("optional zone database", ["scripts/test_zone_database.py"]),
				py("Gregorian measurement smoke", ["scripts/measure_gregorian.py", "--smoke"]),
				py("zone data measurement smoke", ["scripts/measure_zone_data.py", "--smoke"]),
				py("column fixture smoke", ["scripts/measure_zone_roc.py", "--smoke", "--encoding", "columns"]),
				py("TZif fixture smoke", ["scripts/measure_zone_roc.py", "--smoke", "--encoding", "tzif"]),
				py("zone package smoke", ["scripts/measure_zone_package.py", "--smoke"]),
				{ name: "API documentation evidence", program: "scripts/check_api_docs.roc", args: [] },
				{ name: "public documentation examples", program: "scripts/check_doc_examples.roc", args: [] },
				{ name: "immutable API archive controls", program: "scripts/restore_api_docs.roc", args: ["--", "--self-test"] },
				{ name: "native manual acceptance", program: "scripts/build_docs.roc", args: [] },
				{ name: "composed recurrence evidence", program: "scripts/test_local_recurrence.roc", args: [] },
			])
	}
}

application = |roc, work, name, modes| {
	source = "tests/${name}/main.roc"
	[
		{ name: "${name} check", program: roc, args: ["check", source] },
		{ name: "${name} interpreter", program: roc, args: [source] },
	].concat(
		modes.map(
			|mode| {
				binary = "${work}/${name}-${mode}"
				[
					{ name: "${name} ${mode} build", program: roc, args: ["build", source, "--opt=${mode}", "--output=${binary}"] },
					{ name: "${name} ${mode} execution", program: binary, args: [] },
				]
			},
		).fold([], |all, group| all.concat(group)),
	)
}
