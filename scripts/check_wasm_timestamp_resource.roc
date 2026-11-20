#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import cli.OsStr
import cli.Path
import src/BenchmarkProcess
import src/Script

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	root = Path.absolute!(".")?
	source = Path.join(root, "tests/wasm_timestamp_resource")
	work = Path.join(root, ".roc-time-tmp/wasm-timestamp-resource")
	platform_path = Path.join(work, "platform")
	target_dir = Path.join(platform_path, "targets/wasm32")
	Path.create_all!(target_dir)?
	for name in ["main.roc", "Host.roc"] {
		Path.copy!(Path.join(source, "platform/${name}"), Path.join(platform_path, name))?
	}
	core = Json.to_str(Path.display(Path.join(root, "package/main.roc")))
	app_source = Path.read_utf8!(Path.join(source, "main.roc"))?.replace_first("\"../../package/main.roc\"", core)
	entrypoint = Path.join(work, "main.roc")
	Path.write_utf8!(entrypoint, app_source)?
	zig = Script.env_str!("ZIG") ?? "zig"
	if Script.command(OsStr.from_str(zig)).output!(["version"])? != "0.17.0" {
		return Err(WasmFixtureZigVersion("0.17.0"))
	}
	_ = BenchmarkProcess.run!({
		args: [
			zig,
			"build-obj",
			Path.display(Path.join(source, "host.zig")),
			"-target",
			"wasm32-freestanding",
			"-O",
			"ReleaseFast",
			"--cache-dir",
			Path.display(Path.join(work, "zig-cache")),
			"--global-cache-dir",
			Path.display(Path.join(work, "zig-global")),
			"-femit-bin=${Path.display(Path.join(target_dir, "host.wasm"))}",
		],
		cwd: root,
		logs: work,
		label: "wasm-host",
		environment: [],
		timeout_ms: 120000,
	})?
	nightly = Script.roc_nightly!()?
	nightly.run!(["version"])?
	Script.command("node").run!(["--version"])?
	for backend in ["dev", "speed"] {
		program = Path.join(work, "timestamp-${backend}.wasm")
		_ = BenchmarkProcess.run!({
			args: [
				OsStr.display(nightly.program()),
				"build",
				Path.display(entrypoint),
				"--no-cache",
				"--target=wasm32",
				"--opt=${backend}",
				"--output=${Path.display(program)}",
			],
			cwd: root,
			logs: work,
			label: "wasm-build-${backend}",
			environment: [],
			timeout_ms: 120000,
		})?
		result = BenchmarkProcess.run!({
			args: ["node", Path.display(Path.join(source, "replay.mjs")), Path.display(program)],
			cwd: root,
			logs: work,
			label: "wasm-replay-${backend}",
			environment: [],
			timeout_ms: 30000,
		})?
		Script.info!({ label: backend, message: result.stdout.trim() })?
	}
	Ok({})
}
