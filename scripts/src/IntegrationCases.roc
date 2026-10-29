## Routine CI: invariant targets, regressions, public usage and resource gates.
## External oracle comparisons are explicit development tasks.
IntegrationCases := [].{
	Case : { name : Str, program : Str, args : List(Str) }

	all : { roc : Str, work : Str } -> List(Case)
	all = |{ roc, work }| {
		[
			{
				name: "domain and representation diagnostics",
				program: "scripts/check_compile_failures.roc",
				args: [],
			},
		].concat(
			application({
				roc,
				work,
				name: "static_dispatch",
				modes: ["dev"],
			}),
		)
			.concat(
				application({
					roc,
					work,
					name: "codecs",
					modes: ["dev", "speed"],
				}),
			)
			.concat([
				{
					name: "parser and coverage allocation identities",
					program: "scripts/check_resource_identities.roc",
					args: [],
				},
			])
			.concat(
				application({
					roc,
					work,
					name: "zoned_appointment_checks",
					modes: ["dev", "speed"],
				}),
			)
			.concat([
				{
					name: "fuzz replay and bounded search",
					program: "scripts/fuzz.roc",
					args: ["--", "--operation", "all", "--runs", "100", "--seconds", "1", "--seed", "1"],
				},
				{ name: "instrumented fixture controls", program: "scripts/check_fixture_platform.roc", args: [] },
				{ name: "optional zone database", program: "scripts/check_zone_database.roc", args: [] },
				{ name: "API documentation evidence", program: "scripts/check_api_docs.roc", args: [] },
				{ name: "public documentation examples", program: "scripts/check_doc_examples.roc", args: [] },
				{
					name: "immutable API archive controls",
					program: "scripts/restore_api_docs.roc",
					args: ["--", "--self-test"],
				},
				{ name: "native manual acceptance", program: "scripts/build_docs.roc", args: [] },
				{ name: "local recurrence resource budgets", program: "scripts/test_local_recurrence.roc", args: ["--", "--resources-only"] },
			])
	}
}

application : { roc : Str, work : Str, name : Str, modes : List(Str) } -> List(IntegrationCases.Case)
application = |{ roc, work, name, modes }| {
	source = "tests/${name}/main.roc"
	[
		{ name: "${name} check", program: roc, args: ["check", source] },
		{ name: "${name} interpreter", program: roc, args: [source] },
	].concat(
		modes.map(
			|mode| {
				binary = "${work}/${name}-${mode}"
				[
					{
						name: "${name} ${mode} build",
						program: roc,
						args: ["build", source, "--opt=${mode}", "--output=${binary}"],
					},
					{ name: "${name} ${mode} execution", program: binary, args: [] },
				]
			},
		).fold([], |all, group| all.concat(group)),
	)
}
