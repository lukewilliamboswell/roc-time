#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Monotonic
import cli.OsStr
import cli.Path
import src/Measurements
import src/Script

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run measure-gregorian -- [--smoke] [--iterations N] [--runs N] [--warmups N]")
	}
	options = Measurements.parse(args.map(OsStr.display))?
	compiler = Script.roc_nightly!()?
	version = compiler.output!(["version"])?
	output = Path.absolute!(".roc-time-tmp/gregorian-performance")?
	Path.create_all!(output)?
	binary = Path.join(output, "date-bench")
	compiler.cmd(["build", "--opt=speed", OsStr.from_str("--output=${Path.display(binary)}"), "tests/gregorian_performance/main.roc"]).timeout_ms(180000).exec_cmd!()?
	expected = Measurements.checksum(options.iterations).to_str()
	var $workloads = Dict.empty()
	for mode in ["fields", "roundtrip"] {
		var $samples = []
		for index in (0.U64).until(options.warmups + options.runs) {
			before = Monotonic.now!()
			result = Cmd.new(Path.to_os_str(binary)).args_str([options.iterations.to_str(), mode]).timeout_ms(120000).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
			elapsed = (Monotonic.now!() - before).to_f64() / 1000000000
			observed = Str.from_utf8(result.stdout_bytes)?
			_ = Str.from_utf8(result.stderr_bytes)?
			if result.status != Exited(0) or observed.trim() != expected {
				return Script.fail!("${mode}: checksum/status mismatch ${Str.inspect(result)}; expected ${expected}")
			}
			if index >= options.warmups {
				$samples = $samples.append(elapsed)
			}
		}
		stats = Measurements.statistics($samples)?
		$workloads = $workloads.insert(mode, { mean_seconds: stats.mean_seconds, stdev_seconds: stats.stdev_seconds, seconds: $samples })
		Script.info!(mode, "${(stats.mean_seconds * 1000).to_str()} ms +/- ${(stats.stdev_seconds * 1000).to_str()} ms")?
	}
	report = { smoke: options.smoke, compiler: version, backend: "LLVM speed", machine: Script.command("uname").output!(["-m"])?, platform_info: Script.command("uname").output!(["-s", "-r"])?, iterations: options.iterations, warmups: options.warmups, runs: options.runs, checksum: expected, scope: "Process wall time including startup and checksum formatting; scalar dates, no shared input lists. No allocation or retained-memory measurement.", workloads: $workloads }
	path = Path.join(output, "results.json")
	Path.write_utf8!(path, Json.to_str_try(report)?)?
	Script.info!("REPORT", Path.display(path))
}
