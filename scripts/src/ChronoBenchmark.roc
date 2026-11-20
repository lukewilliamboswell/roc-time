import cli.OsStr
import cli.Path
import BenchmarkExpectations
import BenchmarkOptions
import BenchmarkProcess
import FixtureHost
import Script

## Shared build and independent observations for Chrono and the opt-in wider
## comparison. Benchmark allocator artifacts never replace the resource host.
ChronoBenchmark := [].{
	Case : BenchmarkExpectations.Case
	Reference : BenchmarkExpectations.Reference
	Context : {
		work : Path,
		root : Path,
		roc_binary : Path,
		rust_binary : Path,
		target : Str,
		rust_target : Str,
		roc_version : Str,
		rustc : Str,
		rust_pin : Str,
		cargo : Str,
		environment : List((Str, Str)),
		reference : Reference,
	}
	prepare! : BenchmarkOptions.Options => Try(Context, _)
	prepare! = |options| {
		BenchmarkOptions.controls(Path.read_utf8!("tests/benchmark_controls/timing-positive.txt")?)?
		root = Path.absolute!(".")?
		work = Path.absolute!(".roc-time-tmp/chrono-benchmark")?
		Path.create_all!(work)?
		rust_pin = Path.read_utf8!("benchmarks/chrono/rust-version")?.trim()
		rustc = Script.env_str!("RUSTC") ?? "rustc"
		version = BenchmarkProcess.run!({
			args: [rustc, "-Vv"],
			cwd: root,
			logs: work,
			label: "rust-version",
			environment: [],
			timeout_ms: 180000,
		})?
		releases = version.stdout.split_on("\n").keep_if(|line| line.starts_with("release: "))
		if releases != ["release: ${rust_pin}"] {
			return Err(RustVersion(rust_pin))
		}
		cargo = Script.command("cargo").output!(["--version"])?
		environment = [
			("RUSTC", rustc),
			("CARGO_HOME", "${Path.display(root)}/.roc-time-tmp/chrono-cargo"),
			("CARGO_TARGET_DIR", "${Path.display(work)}/cargo-target"),
		]
		if options.fetch {
			_ = BenchmarkProcess.run!({
				args: ["cargo", "fetch", "--locked", "--manifest-path", "benchmarks/chrono/Cargo.toml"],
				cwd: root,
				logs: work,
				label: "cargo-fetch",
				environment,
				timeout_ms: 180000,
			})?
		}
		{ binary: roc_binary, target, version: roc_version } = build_roc!({ options, root, work, allocator: Timing, source: "benchmarks/chrono/main.roc" })?
		rust_target = if (target == "x64musl") "x86_64-unknown-linux-musl" else "aarch64-apple-darwin"
		_ = BenchmarkProcess.run!({
			args: [
				"cargo",
				"build",
				"--offline",
				"--locked",
				"--release",
				"--target",
				rust_target,
				"--manifest-path",
				"benchmarks/chrono/Cargo.toml",
			],
			cwd: root,
			logs: work,
			label: "cargo-build",
			environment,
			timeout_ms: 180000,
		})?
		rust_binary = Path.join(work, "cargo-target/${rust_target}/release/roc-time-chrono-benchmark")
		reference = BenchmarkExpectations.load!({
			profile: "microseconds",
			corpus: Path.utf8("benchmarks/chrono/corpus.jsonl"),
			iterations: options.iterations,
		})?
		if target == "x64musl" {
			help = Script.command("env").output!(["--help"])?
			if !help.contains("--argv0") {
				return Err(Argv0LauncherUnavailable)
			}
		} else if options.argv0 != "benchmark" {
			return Err(Argv0LauncherUnavailable)
		}
		context = {
			work,
			root,
			roc_binary,
			rust_binary,
			target,
			rust_target,
			roc_version,
			rustc: version.stdout,
			rust_pin,
			cargo,
			environment,
			reference,
		}
		expected = Str.join_with(
			reference.cases.map(|case| "${case.day.to_str()}|${case.microseconds.to_str()}|${case.canonical}\n"),
			"",
		)
		for (name, binary) in [("roc-time", roc_binary), ("chrono", rust_binary)] {
			output = execute!(
				context,
				{
					binary,
					argv0: options.argv0,
					mode: "verify",
					iterations: 1,
					warmups: 0,
					samples: 0,
					label: "verify-${name}",
				},
			)?
			if output.stdout != expected {
				return Err(BenchmarkOracleMismatch(name))
			}
		}
		Ok(context)
	}
	build_roc! : { options : BenchmarkOptions.Options, root : Path, work : Path, source : Str, allocator : [Timing, Fixture] } => Try({ binary : Path, target : Str, version : Str }, _)
	build_roc! = |{ options, root, work, source, allocator }| {
		compiler = Script.roc_nightly!()?
		version = compiler.output!(["version"])?
		target = FixtureHost.build!()?
		destination = Path.utf8("benchmarks/chrono/platform/targets/${target}")
		Path.create_all!(destination)?
		for artifact in Path.list!(Path.utf8(".roc-time-tmp/fixture-platform/targets/${target}"))? {
			name = Path.filename(artifact)?.to_str()?
			Path.copy!(artifact, Path.join(destination, name))?
		}
		if allocator == Timing {
			zig = Script.env_str!("ZIG") ?? "zig"
			host_args = [
				zig,
				"build",
				"--build-file",
				"${Path.display(root)}/tests/platform/build.zig",
				"--prefix",
				"${Path.display(work)}/host",
				"--cache-dir",
				"${Path.display(work)}/host-cache",
				"-Doptimize=ReleaseFast",
				"-Dbenchmark-allocator=true",
			]
			_ = BenchmarkProcess.run!({
				args: if (target == "x64musl") host_args.append("-Dtarget=x86_64-linux-musl") else host_args,
				cwd: root,
				logs: work,
				label: "benchmark-host",
				environment: [("ZIG_GLOBAL_CACHE_DIR", "${Path.display(work)}/global-cache")],
				timeout_ms: 180000,
			})?
			Path.copy!(Path.join(work, "host/lib/libhost.a"), Path.join(destination, "libhost.a"))?
		}
		program = OsStr.display(compiler.program())
		_ = BenchmarkProcess.run!({
			args: [program, "check", source],
			cwd: root,
			logs: work,
			label: "roc-check",
			environment: [],
			timeout_ms: 180000,
		})?
		roc_binary = Path.join(work, "roc-${options.roc_opt}${if (options.debug) "-debug" else ""}")
		build_args = [
			program,
			"build",
			source,
			"--opt=${options.roc_opt}",
			"--target=${target}",
			"--output=${Path.display(roc_binary)}",
			"--no-cache",
		]
		_ = BenchmarkProcess.run!({
			args: if (options.debug) build_args.append("--debug") else build_args,
			cwd: root,
			logs: work,
			label: "roc-build",
			environment: [],
			timeout_ms: 180000,
		})?
		Ok({ binary: roc_binary, target, version })
	}
	Execution : {
		binary : Path,
		argv0 : Str,
		mode : Str,
		iterations : U64,
		warmups : U64,
		samples : U64,
		label : Str,
	}
	execute! : Context, Execution => Try(BenchmarkProcess.Output, _)
	execute! = |context, { binary, argv0, mode, iterations, warmups, samples, label }| {
		prefix = if (context.target == "x64musl") ["env", "--argv0=${argv0}"] else []
		command = prefix.concat([
			Path.display(binary),
			mode,
			iterations.to_str(),
			warmups.to_str(),
			samples.to_str(),
		]).concat(context.reference.cases.map(|case| case.text))
		BenchmarkProcess.run!({
			args: command,
			cwd: context.root,
			logs: context.work,
			label,
			environment: [],
			timeout_ms: 180000,
		})
	}
}
