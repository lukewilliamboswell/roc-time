#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import cli.OsStr
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	actual = Script.command("zig").output!(["version"])?
	if actual != "0.17.0" {
		return Script.fail!("zig: expected 0.17.0, found ${actual}")
	}
	Script.info!({ label: "TOOL", message: "Zig ${actual}" })?
	Script.command("pdfinfo").run!(["-v"])
}
