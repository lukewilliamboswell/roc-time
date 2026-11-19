#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import cli.OsStr
import cli.Path
import src/Docs
import src/Script
import src/Manual

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	output = Path.absolute!(Path.utf8(Script.env_str!("DOCS_OUTPUT") ?? ".roc-time-tmp/manual"))?
	version = Script.env_str!("RELEASE_VERSION") ?? "unreleased"
	Docs.build!(output, version)?
	Manual.verify!(Path.join(output, "site"), Bool.True)?
	Script.info!({
		label: "PASS",
		message: "native HTML/PDF manual: ${Path.display(output)}",
	})
}
