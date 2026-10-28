#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Path
import cli.OsStr
import src/Script

Case : { name : Str, fragments : List(Str) }

main! = |_args| {
	nightly = Script.roc_nightly!()?
	# Package loading must work before a rejected program can establish domain
	# safety. A missing import is not the intended failure.
	nightly.run!(["check", "tests/compile_pass/main.roc", "--no-cache"])?
	cases : List(Case)
	cases = Json.parse(Path.read_utf8!("tests/compile_fail/spec.json")?)?
	if cases.is_empty() {
		return Script.fail!("compile-failure inventory is empty")
	}
	for case in cases {
		if case.name.is_empty() or !case.name.to_utf8().all(|byte| (byte >= 'a' and byte <= 'z') or byte == '_') or case.fragments.is_empty() or case.fragments.any(Str.is_empty) {
			return Script.fail!("malformed compile-failure case")
		}
		result = nightly.cmd(["check", OsStr.from_str("tests/compile_fail/${case.name}/main.roc"), "--no-cache"])
			.env("NO_COLOR", "1").stdout(Capture).stderr(Capture).timeout_ms(120000).run!()?
		output = "${Str.from_utf8_lossy(result.stdout_bytes)}${Str.from_utf8_lossy(result.stderr_bytes)}"
		if result.status != Exited(1) or !output.contains("1 error and 0 warnings") or !case.fragments.all(|fragment| output.contains(fragment)) {
			return Script.fail!("${case.name}: intended diagnostic missing or additional errors:\n${output}")
		}
		Script.info!("PASS", "${case.name}: intended compile failure")?
	}
	Script.info!("PASS", "${cases.len().to_str()} intended diagnostics; positive package-loading control")
}
