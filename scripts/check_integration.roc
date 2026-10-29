#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.Monotonic
import cli.OsStr
import cli.Path
import src/IntegrationCases
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	nightly = Script.roc_nightly!()?
	Path.create_all!(".roc-time-tmp")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "integration-")?
	temporary = Path.to_os_str(Path.absolute!(".roc-time-tmp")?)
	cases = IntegrationCases.all({
		roc: OsStr.display(nightly.program()),
		work: Path.display(work),
	})
	start = Monotonic.now!()
	var $index = 0.U64
	var $failed = []
	var $timings = []
	for case in cases {
		$index = $index + 1
		Script.info!({
			label: "[${$index.to_str()}/${cases.len().to_str()}]",
			message: case.name,
		})?
		before = Monotonic.now!()
		result = Cmd.new_str(case.program).args_str(case.args)
			.env("ROC_NIGHTLY", nightly.program())
			.env("ROC_TIME_TMPDIR", temporary)
			.env_str("DOCS_OUTPUT", "${Path.display(work)}/manual")
			.timeout_ms(900000).stdout(Inherit).stderr(Inherit).run!()
		elapsed = (Monotonic.now!() - before) // 1000000
		$timings = $timings.append((elapsed, case.name))
		match result {
			Ok(output) if output.status == Exited(0) => Script.info!({
				label: "PASS",
				message: "${case.name} ${elapsed.to_str()}ms",
			})?
			other => {
				$failed = $failed.append(case.name)
				Script.info!({
					label: "FAIL",
					message: "${case.name} ${elapsed.to_str()}ms: ${Str.inspect(other)}",
				})?
			}
		}
	}
	total = (Monotonic.now!() - start) // 1000000
	Script.info!({
		label: "SUMMARY",
		message: "${(cases.len() - $failed.len()).to_str()} passed, ${$failed.len().to_str()} failed, 0 skipped in ${total.to_str()}ms",
	})?
	for (elapsed, name) in $timings.sort_with(|a, b| if (a.0 > b.0) Before else if (a.0 < b.0) After else Same).take_first(5) {
		Script.info!({
			label: "SLOW",
			message: "${name} ${elapsed.to_str()}ms",
		})?
	}
	if !$failed.is_empty() {
		return Script.fail!("integration failures: ${Str.join_with($failed, ", ")}; artifacts ${Path.display(work)}")
	}
	Ok({})
}
