#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Files
import src/Script
import src/StaticChecks
import src/Text

main! = |args| {
	# Two compilers, two jobs. roc-stable is pinned by Blueprint.lock and runs
	# this repository's scripts, so tooling keeps working when a nightly breaks
	# something. The floating package compiler checks the packages and the check
	# applications, because that is the compiler users install today.
	#
	# The complete contributor gate runs here. The shared release workflow
	# separately builds and tests the exact publication artifacts.
	roc_stable = Script.roc_stable!()?
	roc_nightly = Script.roc_nightly!()?

	Script.section!("COMPILERS")?
	roc_stable.run!(["version"])?
	roc_nightly.run!(["version"])?

	match args.map(OsStr.display) {
		[] => {
			check!(roc_stable, roc_nightly)?
			harness!(roc_nightly)?
			Cmd.new("release-package").args(["test-examples"]).env("RP_COMPILER", roc_nightly.program()).exec_cmd!()
		}
		["--source"] => check!(roc_stable, roc_nightly)
		["--harness"] => harness!(roc_nightly)
		other => Script.fail!("usage: scripts/check_all.roc [-- --source|--harness]; received ${Str.inspect(other)}")
	}
}

check! = |roc_stable, roc_nightly| {
	check_tooling!(roc_stable)?
	check_layout!()?

	Script.section!("PACKAGES")?
	roc_nightly.run!(["check", "package/main.roc"])?
	roc_nightly.run!(["test", "package/main.roc"])?
	roc_nightly.run!(["check", "tzdb/package/main.roc"])?

	Env.with_temp_dir!(|temporary| check_applications!(roc_nightly, temporary))?
	Script.info!("\nPASS", "all checks")
}

harness! = |roc_nightly| {
	Script.section!("INTEGRATION CASES")?
	Cmd.new("scripts/check_integration.roc").env("ROC_NIGHTLY", roc_nightly.program()).exec_cmd!()?
	Script.info!("\nPASS", "harness")
}

check_tooling! = |roc_stable| {
	Script.section!("TOOLING")?
	roc_stable.run!(["fmt", "--check", "scripts", "Blueprint.roc"])?
	for file in ["Text", "StaticChecks", "ApiArchive", "ApiInventory", "DocExamples", "ResourceMetrics", "Measurements", "ZoneArchive", "NativeMetrics", "ZoneMeasurement", "ZonePrototype"] {
		roc_stable.run!(["test", Path.to_os_str(Path.join("scripts/src", "${file}.roc"))])?
	}
	for script in Files.direct_roc_files!("scripts")? {
		roc_stable.run!(["check", Path.to_os_str(script)])?
	}
	roc_stable.run!(["test", "scripts/build_docs.roc"])?
	roc_stable.run!(["test", "scripts/fuzz.roc"])
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

# Four check applications drive pure modules through the public package, with
# their output recorded under tests/examples/<name>.txt. Two of them exercise
# the exact pure module of a public example: Roc imports cannot leave an
# application's directory, so a copy is staged with that module beside it and
# the package named by absolute path. Each runs interpreted and as a native
# build, from an empty working directory.
check_applications! = |roc_nightly, temporary| {
	Script.section!("CHECK APPLICATIONS")?
	core = Path.display(Path.absolute!("package/main.roc")?)
	staged = Path.join(temporary, "staged")
	Path.create_all!(staged)?
	var $checks = []
	for name in ["schedule_definition_checks", "utc_cancellations_checks"] {
		$checks = $checks.append({ name, directory: Path.join("tests", name) })
	}
	for (name, file) in [("clock_deadline_checks", "examples/clock_deadline/Deadline.roc"), ("invoice_report_checks", "examples/invoice_report/InvoiceReport.roc")] {
		directory = Path.join(staged, name)
		Path.copy_dir!(Path.join("tests", name), directory)?
		Path.copy!(file, Path.join(directory, Files.name(file)))?
		main = Path.join(directory, "main.roc")
		Path.write_utf8!(main, Text.rewrite_dependency(Path.read_utf8!(main)?, "time", core)?)?
		$checks = $checks.append({ name, directory })
	}
	build = Path.join(temporary, "build")
	empty = Path.join(temporary, "empty-cwd")
	Path.create_all!(build)?
	Path.create_all!(empty)?
	for check in $checks {
		Script.info!("APP", check.name)?
		expected = Path.read_utf8!(Path.join("tests/examples", "${check.name}.txt"))?
		roc = |args| roc_nightly.cmd(args).cwd(check.directory)
		roc(["check", "main.roc", "--no-cache"]).exec_cmd!()?
		verify!(check.name, "interpreted", roc(["main.roc", "--no-cache"]).exec_output!()?.stdout_utf8, expected)?
		binary = Path.join(build, check.name)
		roc(["build", "main.roc", "--opt=dev", OsStr.from_str("--output=${Path.display(binary)}"), "--no-cache"]).exec_cmd!()?
		verify!(check.name, "native", Cmd.new(Path.to_os_str(binary)).cwd(empty).exec_output!()?.stdout_utf8, expected)?
	}
	Script.info!("PASS", "${$checks.len().to_str()} check applications match their recorded output")
}

verify! = |name, mode, actual, expected|
	if actual == expected {
		Ok({})
	} else {
		Script.fail!("unexpected ${mode} output from ${name}:\n${actual}")
	}
