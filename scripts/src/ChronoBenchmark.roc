import cli.OsStr
import cli.Path
import BenchmarkOptions
import BenchmarkProcess
import FixtureHost
import Script

## Shared build and independent observations for Chrono and the opt-in wider
## comparison. Benchmark allocator artifacts never replace the resource host.
ChronoBenchmark := [].{
	Case : { text : Str, day : I64, microseconds : I64, canonical : Str }
	Reference : { cases : List(Case), checksums : Dict(Str, U64) }
	Context : { work : Path, root : Path, roc_binary : Path, rust_binary : Path, target : Str, rust_target : Str, roc_version : Str, rustc : Str, rust_pin : Str, cargo : Str, environment : List((Str, Str)), reference : Reference }
	prepare! : BenchmarkOptions.Options => Try(Context, _)
	prepare! = |options| {
		BenchmarkOptions.controls(Path.read_utf8!("tests/benchmark_controls/timing-positive.txt")?)?
		compiler = Script.roc_nightly!()?
		roc_version = compiler.output!(["version"])?
		root = Path.absolute!(".")?
		work = Path.absolute!(".roc-time-tmp/chrono-benchmark")?
		Path.create_all!(work)?
		rust_pin = Path.read_utf8!("benchmarks/chrono/rust-version")?.trim()
		rustc = Script.env_str!("RUSTC") ?? "rustc"
		version = BenchmarkProcess.run!([rustc, "-Vv"], root, work, "rust-version", [], 180000)?
		releases = version.stdout.split_on("\n").keep_if(|line| line.starts_with("release: "))
		if releases != ["release: ${rust_pin}"] {
			return Err(RustVersion(rust_pin))
		}
		cargo = Script.command("cargo").output!(["--version"])?
		environment = [("RUSTC", rustc), ("CARGO_HOME", "${Path.display(root)}/.roc-time-tmp/chrono-cargo"), ("CARGO_TARGET_DIR", "${Path.display(work)}/cargo-target")]
		if options.fetch {
			_ = BenchmarkProcess.run!(["cargo", "fetch", "--locked", "--manifest-path", "benchmarks/chrono/Cargo.toml"], root, work, "cargo-fetch", environment, 180000)?
		}
		target = FixtureHost.build!()?
		zig = Script.env_str!("ZIG") ?? "zig"
		host_args = [zig, "build", "--build-file", "${Path.display(root)}/tests/platform/build.zig", "--prefix", "${Path.display(work)}/host", "--cache-dir", "${Path.display(work)}/host-cache", "-Doptimize=ReleaseFast", "-Dbenchmark-allocator=true"]
		_ = BenchmarkProcess.run!(if (target == "x64musl") host_args.append("-Dtarget=x86_64-linux-musl") else host_args, root, work, "benchmark-host", [("ZIG_GLOBAL_CACHE_DIR", "${Path.display(work)}/global-cache")], 180000)?
		destination = Path.utf8("benchmarks/chrono/platform/targets/${target}")
		Path.create_all!(destination)?
		for artifact in Path.list!(Path.utf8(".roc-time-tmp/fixture-platform/targets/${target}"))? {
			name = Path.filename(artifact)?.to_str()?
			Path.copy!(artifact, Path.join(destination, name))?
		}
		Path.copy!(Path.join(work, "host/lib/libhost.a"), Path.join(destination, "libhost.a"))?
		rust_target = if (target == "x64musl") "x86_64-unknown-linux-musl" else "aarch64-apple-darwin"
		program = OsStr.display(compiler.program())
		_ = BenchmarkProcess.run!([program, "check", "benchmarks/chrono/main.roc"], root, work, "roc-check", [], 180000)?
		roc_binary = Path.join(work, "roc-${options.roc_opt}${if (options.debug) "-debug" else ""}")
		build_args = [program, "build", "benchmarks/chrono/main.roc", "--opt=${options.roc_opt}", "--target=${target}", "--output=${Path.display(roc_binary)}", "--no-cache"]
		_ = BenchmarkProcess.run!(if (options.debug) build_args.append("--debug") else build_args, root, work, "roc-build", [], 180000)?
		_ = BenchmarkProcess.run!(["cargo", "build", "--offline", "--locked", "--release", "--target", rust_target, "--manifest-path", "benchmarks/chrono/Cargo.toml"], root, work, "cargo-build", environment, 180000)?
		rust_binary = Path.join(work, "cargo-target/${rust_target}/release/roc-time-chrono-benchmark")
		reference = reference!(Path.utf8("benchmarks/chrono/corpus.jsonl"), options.iterations, work)?
		help = Script.command("env").output!(["--help"])?
		if !help.contains("--argv0") {
			return Err(Argv0LauncherUnavailable)
		}
		context = { work, root, roc_binary, rust_binary, target, rust_target, roc_version, rustc: version.stdout, rust_pin, cargo, environment, reference }
		expected = Str.join_with(reference.cases.map(|case| "${case.day.to_str()}|${case.microseconds.to_str()}|${case.canonical}\n"), "")
		for (name, binary) in [("roc-time", roc_binary), ("chrono", rust_binary)] {
			output = execute!(context, binary, options.argv0, "verify", 1, 0, 0, "verify-${name}")?
			if output.stdout != expected {
				return Err(BenchmarkOracleMismatch(name))
			}
		}
		Ok(context)
	}
	reference! : Path, U64, Path => Try(Reference, _)
	reference! = |corpus, iterations, logs| {
		python = Script.env_str!("PYTHON") ?? "python3"
		result = BenchmarkProcess.run!([python, "scripts/reference_benchmarks.py", Path.display(corpus), iterations.to_str()], Path.absolute!(".")?, logs, "reference", [], 180000)?
		reference : Reference
		reference = Json.parse(result.stdout)?
		if reference.cases.is_empty() or reference.cases.len() > 4096 or BenchmarkOptions.modes.any(|mode| !reference.checksums.contains(mode)) {
			return Err(BenchmarkReference)
		}
		Ok(reference)
	}
	execute! : Context, Path, Str, Str, U64, U64, U64, Str => Try({ stdout : Str, stderr : Str }, _)
	execute! = |context, binary, argv0, mode, iterations, warmups, samples, label| {
		command = ["env", "--argv0=${argv0}", Path.display(binary), mode, iterations.to_str(), warmups.to_str(), samples.to_str()].concat(context.reference.cases.map(|case| case.text))
		BenchmarkProcess.run!(command, context.root, context.work, label, [], 180000)
	}
}
