#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Path
import cli.OsStr
import src/Script

main! = |_args| {
	for (program, args, expected) in [
		("zig", ["version"], "0.17.0"),
		("python3", ["--version"], "Python ${Path.read_utf8!("benchmarks/python-version")?.trim()}"),
		("rustc", ["--version"], "rustc ${Path.read_utf8!("benchmarks/chrono/rust-version")?.trim()} "),
	] {
		actual = Script.command(OsStr.from_str(program)).output!(args.map(OsStr.from_str))?
		if !actual.starts_with(expected) {
			return Script.fail!("${program}: expected ${expected}, found ${actual}")
		}
		Script.info!("TOOL", actual)?
	}
	Script.command("cargo").run!(["--version"])?
	Script.command("pdfinfo").run!(["-v"])
}
