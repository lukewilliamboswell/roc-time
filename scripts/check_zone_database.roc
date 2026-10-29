#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import src/FixtureHost
import src/NativeMetrics
import src/OracleStages
import src/Script
import src/ZoneDistribution
import src/ZoneVerification

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	directory = Path.absolute!("tzdb/package")?
	manifest = ZoneVerification.integrity!(directory)?
	compiler = Script.roc_nightly!()?
	program = OsStr.display(compiler.program())
	cwd = Path.absolute!(".")?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "zone-replay-")?
	copied = Path.join(work, "package")
	Path.create_dir!(copied)?
	for file in Path.list!(directory)? {
		name = Path.filename(file)?.to_str()?
		Path.copy!(file, Path.join(copied, name))?
	}
	ZoneVerification.verify!({
		directory: copied,
		manifest,
		compiler,
	})?
	app_source = "tests/zone_database/main.roc"
	_ = OracleStages.run!({
		command: [program, "check", app_source],
		cwd,
		logs: work,
		label: "provider-check",
		timeout_ms: 180000,
	})?
	_ = OracleStages.run!({
		command: [program, "--opt=interpreter", app_source],
		cwd,
		logs: work,
		label: "provider-interpret",
		timeout_ms: 180000,
	})?
	provider = Path.join(work, "provider")
	_ = OracleStages.run!({
		command: [program, "build", app_source, "--output=${Path.display(provider)}"],
		cwd,
		logs: work,
		label: "provider-build",
		timeout_ms: 180000,
	})?
	_ = OracleStages.run!({
		command: [Path.display(provider)],
		cwd,
		logs: work,
		label: "provider-run",
		timeout_ms: 180000,
	})?
	target = FixtureHost.build!()?
	for mode in ["dev", "speed"] {
		binary = Path.join(work, "lookup-${mode}")
		_ = OracleStages.run!({
			command: [
				program,
				"build",
				"tests/zone_database/resource/main.roc",
				"--opt=${mode}",
				"--debug",
				"--target=${target}",
				"--output=${Path.display(binary)}",
				"--no-cache",
			],
			cwd,
			logs: work,
			label: "resource-build-${mode}",
			timeout_ms: 180000,
		})?
		for (name, index) in ["Australia/Melbourne", "US/Eastern", "Pacific/Apia", "Etc/UTC"].map_with_index(|name, index| (name, index)) {
			canonical = manifest.names.get(name)?
			expected = manifest.transition_expectations.get(canonical)?
			output = Cmd.new(Path.to_os_str(binary)).args_str([name]).timeout_ms(10000).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
			Path.write_bytes!(Path.join(work, "lookup-${mode}-${index.to_str()}.stdout"), output.stdout_bytes)?
			Path.write_bytes!(Path.join(work, "lookup-${mode}-${index.to_str()}.stderr"), output.stderr_bytes)?
			stdout = Str.from_utf8(output.stdout_bytes)?
			stderr = Str.from_utf8(output.stderr_bytes)?
			metrics = NativeMetrics.parse(stderr)?
			budget = if (mode == "dev") 0.U64 else 1
			if output.status != Exited(0) or stdout != "${canonical}|${expected.checksum.to_str()}\n" or metrics.work.len() != 2 or metrics.work.get(0)? > budget or metrics.work.get(1)? != expected.count or metrics.traces.map(|trace| trace.mark) != [1, 2] {
				return Err(ZoneResourceObservation(name, mode))
			}
			first = metrics.traces.first()?.allocations
			second = metrics.traces.last()?.allocations
			if second < first {
				return Err(NonmonotonicAllocationCounter)
			}
			if second - first != metrics.work.get(0)? {
				return Err(TraceAllocationDisagreement)
			}
			Script.info!({
				label: "PASS",
				message: "${mode} ${name}: ${stderr.trim()}",
			})?
		}
	}
	# A real corrupted wheel must fail integrity before archive decoding.
	invalid = Path.join(work, "corrupted.whl")
	Path.write_utf8!(invalid, "corrupted wheel")?
	stable = Script.roc_stable!()?
	invalid_output = Path.join(work, "invalid-output")
	rejected = stable.cmd([
		"scripts/generate_zone_database.roc",
		"--",
		Path.to_os_str(invalid),
		Path.to_os_str(invalid_output),
	]).timeout_ms(30000).manage_tree(Bool.True).output_limit(1048576).stdout(Capture).stderr(Capture).run!()?
	diagnostic = "${Str.from_utf8(rejected.stdout_bytes)?}${Str.from_utf8(rejected.stderr_bytes)?}"
	match rejected.status {
		Exited(code) if code != 0 and diagnostic.contains("Program exited with error: WheelIntegrity") => {}
		_ => return Err(BrokenIntegrityControl)
	}
	if Path.exists!(invalid_output)? {
		return Err(InvalidWheelCreatedOutput)
	}
	Script.info!({
		label: "EVIDENCE",
		message: Path.display(work),
	})
}
