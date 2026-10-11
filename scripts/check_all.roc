#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Path
import src/Files
import src/Script

main! = |_args| {
	# Two compilers, two jobs. roc-stable is pinned by Blueprint.lock and runs
	# this repository's scripts, so tooling keeps working when a nightly breaks
	# something. The package compiler checks the packages and examples.
	roc_stable = Script.roc_stable!()?
	roc_nightly = Script.roc_nightly!()?

	Script.section!("COMPILERS")?
	roc_stable.run!(["version"])?
	roc_nightly.run!(["version"])?

	Script.section!("TOOLING")?
	roc_stable.run!(["fmt", "--check", "scripts", "Blueprint.roc"])?
	for script in Files.direct_roc_files!("scripts")? {
		roc_stable.run!(["check", Path.to_os_str(script)])?
	}

	# The Python harness still owns the package, oracle, fuzz, resource and
	# release checks. It selects the package compiler through ROC.
	Script.section!("PACKAGE")?
	python = Script.env_str!("PYTHON") ?? "python3"
	Script.info!("+", "${python} scripts/all_tests.py")?
	Cmd.new_str(python)
		.args(["scripts/all_tests.py"])
		.env("ROC", roc_nightly.program())
		.exec_cmd!()
}
