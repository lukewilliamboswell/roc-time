#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/FixtureHost
import src/Script

Fixture : { name : Str, source : Str, stdout : Str, cases : List(List(Str)), failure_args : List(Str) }

main! = |_args| {
	target = FixtureHost.build!()?
	nightly = Script.roc_nightly!()?
	fixtures : List(Fixture)
	fixtures = Json.parse(Path.read_utf8!("tests/resource_identities/spec.json")?)?
	if fixtures.is_empty() {
		return Err(EmptyFixtures)
	}
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "resource-identities-")?
	for fixture in fixtures {
		if fixture.cases.is_empty() or fixture.failure_args.is_empty() {
			return Err(EmptyCases)
		}
		for mode in ["dev", "speed"] {
			binary = Path.join(work, "${fixture.name}-${mode}")
			nightly.cmd(["build", OsStr.from_str(fixture.source), OsStr.from_str("--opt=${mode}"), OsStr.from_str("--target=${target}"), OsStr.from_str("--output=${Path.display(binary)}")]).timeout_ms(180000).exec_cmd!()?
			for args in fixture.cases {
				result = Cmd.new(Path.to_os_str(binary)).args_str(args).timeout_ms(10000).stdout(Capture).stderr(Capture).run!()?
				stdout = Str.from_utf8(result.stdout_bytes)?
				stderr = Str.from_utf8(result.stderr_bytes)?
				if result.status != Exited(0) or stdout != fixture.stdout or !stderr.ends_with(" work=0,0\n") {
					return Script.fail!("${fixture.name}/${mode}: changed output or allocation traffic: ${Str.inspect(result)}")
				}
			}
			failed = Cmd.new(Path.to_os_str(binary)).args_str(fixture.failure_args).timeout_ms(10000).stdout(Capture).stderr(Capture).run!()?
			_ = Str.from_utf8(failed.stdout_bytes)?
			failure_text = Str.from_utf8(failed.stderr_bytes)?
			match failed.status {
				Exited(code) if code != 0 and failure_text.contains("ROC_ASSERT_FAILED") => {}
				_ => return Script.fail!("${fixture.name}/${mode}: allocation failure control did not fail normally")
			}
			Script.info!("PASS", "${fixture.name} ${mode}: ${fixture.cases.len().to_str()} runtime cases, zero scoped allocation, failing control")?
		}
	}
	Ok({})
}
