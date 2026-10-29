#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/FixtureBatch
import src/FixtureOracles
import src/OracleStages
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |args| {
	kind = match args.map(OsStr.display) {
		[selected] if ["civil", "date", "timed"].contains(selected) => selected
		_ => return Err(Arguments)
	}
	root_name = match kind {
		"civil" => "civil_query_checks"
		"date" => "date_export_checks"
		_ => "timed_export_checks"
	}
	source = Path.absolute!(Path.utf8("tests/${root_name}/main.roc"))?
	directory = Path.utf8("tests/${root_name}")
	expected_hashes = match kind {
		"civil" => Dict.from_list([
			("reference.py", "dbe36a1f7fc7cf65f4554285adaee50e5d2119c114a58316f95796f47ad6ba44"),
			("cases.jsonl", "5cd11c1503af724c9ffa6dff9277f0454d0a6d381cabd76cf8a2c91b96042ba0"),
		])
		"date" => Dict.from_list([("cases.jsonl", "a8144deb5fc5422ca6cabba7c17a31b7ad229ac29d0b05ed5dd28fb2a2c7647a")])
		_ => Json.parse(Path.read_utf8!(Path.join(directory, "integrity.json"))?)?
	}
	for (file, expected) in expected_hashes.to_list() {
		actual = Script.command("sha256sum").output!([Path.to_os_str(Path.join(directory, file))])?
		if !actual.starts_with("${expected} ") {
			return Err(FixtureIntegrity(file))
		}
	}
	cases = FixtureOracles.load(kind, Path.read_utf8!(Path.join(directory, "cases.jsonl"))?)?
	first = cases.first()?
	if kind != "civil" {
		for wrong in ["", "null", "{}", "[]", "{broken"] {
			if FixtureOracles.is_matching_output(first.expected, wrong) {
				return Err(BrokenOutputControl)
			}
		}
	}
	match first.expected {
		Date(value) => if FixtureOracles.is_matching_output(first.expected, Json.to_str({ ..value, dates: [] })) {
			return Err(BrokenSemanticOutputControl)
		}
		Timed(value) => if FixtureOracles.is_matching_output(first.expected, Json.to_str({ ..value, occurrences: [] })) {
			return Err(BrokenSemanticOutputControl)
		}
		_ => {}
	}
	if kind == "date" and FixtureOracles.is_matching_output(cases.get(6)?.expected, "OutOfRange(\"wrong-field\")") {
		return Err(BrokenErrorOutputControl)
	}
	compiler = Script.roc_nightly!()?
	program = OsStr.display(compiler.program())
	cwd = Path.absolute!(".")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "fixture-oracles-${kind}-")?
	_ = OracleStages.run!({
		command: [program, "check", Path.display(source)],
		cwd,
		logs: work,
		label: "check",
		timeout_ms: 180000,
	})?
	smoke = OracleStages.run!({
		command: [program, Path.display(source), "--"].concat(first.input),
		cwd,
		logs: work,
		label: "interpret",
		timeout_ms: 180000,
	})?
	if !FixtureOracles.is_matching_output(first.expected, smoke.stdout) {
		return Err(InterpreterFixtureMismatch)
	}
	for mode in ["dev", "speed"] {
		binary = Path.join(work, mode)
		_ = OracleStages.run!({
			command: [program, "build", Path.display(source), "--opt=${mode}", "--output=${Path.display(binary)}"],
			cwd,
			logs: work,
			label: "build-${mode}",
			timeout_ms: 180000,
		})?
		FixtureBatch.replay!({
			binary,
			cases,
			work,
			prefix: mode,
		})?
		if kind == "civil" {
			output = OracleStages.run!({
				command: [Path.display(binary), "cycle"],
				cwd,
				logs: work,
				label: "cycle-${mode}",
				timeout_ms: 180000,
			})?
			if output.stdout != "PASS 146097 Gregorian days\n" {
				return Err(MissingCycle)
			}
			failure = Cmd.new(Path.to_os_str(binary)).args_str(["cycle", "wrong-week"]).timeout_ms(30000).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
			diagnostic = "${Str.from_utf8(failure.stdout_bytes)?}${Str.from_utf8(failure.stderr_bytes)?}"
			match failure.status {
				Exited(code) if code != 0 and diagnostic.contains("Gregorian query differs from independent day walk") => {}
				_ => return Err(BrokenCycleFailureControl)
			}
		} else {
			counterexamples = if (kind == "date") [(cases.get(1)?, first)] else [(cases.get(1)?, first), (cases.last()?, cases.get(cases.len() - 2)?)]
			for ((actual, expected), index) in counterexamples.map_with_index(|pair, index| (pair, index)) {
				output = OracleStages.run!({
					command: [Path.display(binary)].concat(actual.input),
					cwd,
					logs: work,
					label: "wrong-${mode}-${index.to_str()}",
					timeout_ms: 180000,
				})?
				if FixtureOracles.is_matching_output(expected.expected, output.stdout) {
					return Err(BrokenNativeComparisonControl)
				}
			}
		}
		Script.info!({
			label: "PASS",
			message: "${kind}/${mode}: ${cases.len().to_str()} independent fixtures, interpreter smoke, native failure controls; ${Path.display(work)}",
		})?
	}
	Ok({})
}
