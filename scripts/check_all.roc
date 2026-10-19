#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.Path
import cli.Stderr
import src/Files
import src/Script
import src/StaticChecks

main! = |_args| {
	# Two compilers, two jobs. roc-stable is pinned by Blueprint.lock and runs
	# this repository's scripts, so tooling keeps working when a nightly breaks
	# something. The floating package compiler checks the packages and examples,
	# because that is the compiler users install today.
	roc_stable = Script.roc_stable!()?
	roc_nightly = Script.roc_nightly!()?

	Script.section!("COMPILERS")?
	roc_stable.run!(["version"])?
	roc_nightly.run!(["version"])?

	check_tooling!(roc_stable)?
	check_layout!()?

	Script.section!("PACKAGES")?
	roc_nightly.run!(["check", "package/main.roc"])?
	roc_nightly.run!(["test", "package/main.roc"])?
	roc_nightly.run!(["check", "tzdb/package/main.roc"])?

	roc_stable.run!(["scripts/test_examples.roc"])?

	# The Python harness still owns the compile-failure, static-dispatch, codec,
	# resource, oracle, fuzz, measurement and documentation checks. It selects
	# the package compiler through ROC.
	Script.section!("PYTHON HARNESS")?
	python = Script.env_str!("PYTHON") ?? "python3"
	Script.info!("+", "${python} scripts/python_harness.py")?
	Cmd.new_str(python).args(["scripts/python_harness.py"]).env("ROC", roc_nightly.program()).exec_cmd!()?
	roc_stable.run!(["scripts/test_local_recurrence.roc"])?

	# A release dry run: the exact bundles and examples archive a release would
	# publish, under a version no release uses.
	Env.with_temp_dir!(
		|temporary|
			roc_stable
				.cmd(["scripts/build_release.roc"])
				.env("RELEASE_VERSION", "999.999.999")
				.env("RELEASE_NOTES_FILE", "docs/releases/0.3.0.adoc")
				.env("OUTPUT_DIR", Path.to_os_str(Path.join(temporary, "dist")))
				.exec_cmd!(),
	)?
	Script.info!("\nPASS", "all checks")
}

check_tooling! = |roc_stable| {
	Script.section!("TOOLING")?
	roc_stable.run!(["fmt", "--check", "scripts", "Blueprint.roc"])?
	for file in ["Text", "StaticChecks", "Release"] {
		roc_stable.run!(["test", Path.to_os_str(Path.join("scripts/src", "${file}.roc"))])?
	}
	for script in Files.direct_roc_files!("scripts")? {
		roc_stable.run!(["check", Path.to_os_str(script)])?
	}
	roc_stable.run!(["test", "scripts/build_docs.roc"])
}

check_layout! = || {
	Script.section!("LAYOUT")?
	read! = |paths| paths.map_try!(|path| Ok({ path: Path.display(path), source: Path.read_utf8!(path)? }))
	scripts = read!(Files.direct_roc_files!("scripts")?)?
	mains = read!(Files.all_roc_files!("examples")?.keep_if(|path| Files.name(path) == "main.roc"))?
	var $sources = read!(["Blueprint.roc"])?
	for directory in ["benchmarks", "examples", "package", "scripts", "tests", "tzdb"] {
		$sources = $sources.concat(read!(Files.all_roc_files!(directory)?)?)
	}
	problems = StaticChecks.pin_problems(Path.exists!(".roc-version")?, $sources)
		.concat(StaticChecks.example_problems(mains))
		.concat(StaticChecks.shebang_problems(scripts))
	for problem in problems {
		Stderr.line!("error: ${problem}")?
	}
	if problems.is_empty() {
		Script.info!("PASS", "no compiler pins in ${$sources.len().to_str()} Roc files; ${mains.len().to_str()} examples use relative package paths; ${scripts.len().to_str()} scripts run on roc-stable")
	} else {
		Err(LayoutProblems(problems.len()))
	}
}
