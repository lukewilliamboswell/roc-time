#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }
import cli.OsStr
import cli.Path
import cli.Cmd
import src/LocalOracle
import src/FixtureHost
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	nightly = Script.roc_nightly!()?
	stable = Script.roc_stable!()?
	nightly.run!(["version"])?
	stable.run!(["test", "scripts/src/LocalOracle.roc"])?
	expected = Path.read_utf8!("tests/oracles/local-recurrence-v1.tsv")?
	digest = Script.command("sha256sum").output!(["tests/oracles/local-recurrence-v1.tsv"])?
	if !digest.starts_with("975cf0ed3e5a921611313f9a5e3080624c372cd891c56b167c5dee00b5ae0641 ") {
		return Script.fail!("composed recurrence corpus digest changed; review its independent expectations")
	}
	LocalOracle.controls(expected)?
	# The same pinned host drives the resource and composed recurrence checks.
	target = FixtureHost.build!()?
	Path.create_all!(".roc-time-tmp/local-recurrence")?
	nightly.run!(["check", "tests/local_recurrence/main.roc"])?
	nightly.run!(["--opt=interpreter", "tests/local_recurrence/main.roc"])?
	for mode in ["dev", "speed"] {
		binary = Path.display(Path.absolute!(Path.utf8(".roc-time-tmp/local-recurrence/${mode}"))?)
		nightly.run!([
			"build",
			"tests/local_recurrence/native/main.roc",
			"--opt=${mode}",
			"--target=${target}",
			"--output=${binary}",
		])?
		actual = Cmd.new_str(binary).timeout_ms(10000).exec_output!()?.stdout_utf8
		LocalOracle.verify({
			expected,
			actual,
		})?
		Script.info!({
			label: "PASS",
			message: "108 composed local recurrence cases: ${mode}/${target}; oracle negative controls",
		})?
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
