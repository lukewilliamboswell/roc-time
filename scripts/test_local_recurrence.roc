#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }
import cli.OsStr
import cli.Path
import cli.Cmd
import src/OracleManifest
import src/OracleStages
import src/LocalOracle
import src/FixtureHost
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |args| {
	scope = match args.map(OsStr.display) {
		[] => WithOracle
		["--resources-only"] => ResourcesOnly
		_ => return Err(Arguments)
	}
	nightly = Script.roc_nightly!()?
	nightly.run!(["version"])?
	# The same pinned host drives the resource and composed recurrence checks.
	target = FixtureHost.build!()?
	Path.create_all!(".roc-time-tmp/local-recurrence")?
	work = Path.absolute!(".roc-time-tmp/local-recurrence")?
	if scope == WithOracle {
		verify_reference!({ compiler: nightly, target, work })?
	}
	for mode in ["dev", "speed"] {
		resource = Path.display(Path.absolute!(Path.utf8(".roc-time-tmp/local-recurrence/resource-${mode}"))?)
		nightly.run!([
			"build",
			"tests/local_recurrence/resource/main.roc",
			"--opt=${mode}",
			"--target=${target}",
			"--output=${resource}",
		])?
		short = Cmd.new_str(resource).args(["1971", "4096"]).timeout_ms(5000).exec_output!()?.stdout_utf8
		vast = Cmd.new_str(resource).args(["200000", "4096"]).timeout_ms(5000).exec_output!()?.stdout_utf8
		if short != vast {
			return Script.fail!("local schedule prefix allocation/work depends on horizon")
		}
		for stage in ["construction", "first", "resume"] {
			match Cmd.new_str(resource).args_str(["200000", "0", stage]).timeout_ms(5000).exec_output!() {
				Err(NonZeroExitCode(value)) if value.stderr_utf8_lossy.contains("ROC_ASSERT_FAILED") => {}
				_ => return Script.fail!("local recurrence ${stage} allocation negative control did not fail as intended")
			}
		}
		Script.info!({
			label: "PASS",
			message: "local prefix ${mode}/${target} construction/first/resume bytes and work: ${short.trim()}; 4 KiB per stage; failing control",
		})?
	}
	Ok({})
}

verify_reference! : { compiler : Script.Command, target : Str, work : Path } => Try({}, _)
verify_reference! = |{ compiler, target, work }| {
	Script.roc_stable!()?.run!(["test", "scripts/src/LocalOracle.roc"])?
	fields = OracleManifest.parse_fields(Path.read_utf8!("tests/oracles/local-recurrence-manifest.toml")?)?
	generator : Str
	generator = Json.parse(fields.get("generator")?)?
	model : Str
	model = Json.parse(fields.get("model")?)?
	for (path, key) in [(generator, "generator_sha256"), (model, "model_sha256")] {
		expected_digest : Str
		expected_digest = Json.parse(fields.get(key)?)?
		if hash_file!(Path.utf8(path))? != expected_digest {
			return Err(ReferenceSourceIntegrity(path))
		}
	}
	generated = OracleStages.run!({
		command: [OsStr.display(compiler.program()), generator],
		cwd: Path.absolute!(".")?,
		logs: work,
		label: "generate-reference",
	})?
	corpus = Path.join(work, "expected.tsv")
	Path.write_utf8!(corpus, generated.stdout)?
	expected_digest : Str
	expected_digest = Json.parse(fields.get("corpus_sha256")?)?
	if hash_file!(corpus)? != expected_digest {
		return Err(ReferenceCorpusIntegrity)
	}
	expected = generated.stdout
	LocalOracle.controls(expected)?
	compiler.run!(["check", "tests/local_recurrence/main.roc"])?
	compiler.run!(["--opt=interpreter", "tests/local_recurrence/main.roc"])?
	for mode in ["dev", "speed"] {
		binary = Path.join(work, mode)
		compiler.run!([
			"build",
			"tests/local_recurrence/native/main.roc",
			OsStr.from_str("--opt=${mode}"),
			OsStr.from_str("--target=${target}"),
			OsStr.from_str("--output=${Path.display(binary)}"),
		])?
		actual = Cmd.new(Path.to_os_str(binary)).timeout_ms(10000).exec_output!()?.stdout_utf8
		LocalOracle.verify({ expected, actual })?
		Script.info!({ label: "PASS", message: "108 composed local recurrence cases: ${mode}/${target}; oracle negative controls" })?
	}
	Ok({})
}

hash_file! : Path => Try(Str, _)
hash_file! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
