#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import cli.Cmd
import cli.Duration
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Files
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	if Script.command("uname").output!(["-s"])? != "Linux" {
		return Script.fail!("fixture backtraces currently require Linux and gdb")
	}
	for directory in Files.sort_paths(Path.list!(".roc-time-tmp")?) {
		if Files.name(directory).starts_with("fixture-verification-") {
			binary = Path.join(directory, "probe-dev")
			if Path.exists!(binary)? {
				result = Cmd.new("gdb").args([
					"--batch",
					"-ex",
					"set pagination off",
					"-ex",
					"run",
					"-ex",
					"bt full",
					"-ex",
					"info registers",
					"--args",
					Path.to_os_str(binary),
					"42",
					"43",
				]).timeout(Duration.seconds(30)).manage_tree(True)
					.output_limit(MaxBytes(1048576)).stdout(Capture).stderr(Capture).run!()?
				Path.write_bytes!(Path.join(directory, "debugger.stdout"), result.stdout_bytes)?
				Path.write_bytes!(Path.join(directory, "debugger.stderr"), result.stderr_bytes)?
				Stderr.line!(Str.from_utf8_lossy(result.stdout_bytes))?
				Stderr.line!(Str.from_utf8_lossy(result.stderr_bytes))?
				if result.status != Exited(0) {
					return Err(DebuggerStatus(result.status))
				}
				return Ok({})
			}
		}
	}
	Script.info!({ label: "SKIP", message: "no compiled fixture probe available for a backtrace" })
}
