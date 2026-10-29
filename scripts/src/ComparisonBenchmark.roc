import cli.OsStr
import cli.Path
import BenchmarkOptions
import BenchmarkProcess
import ChronoBenchmark
import ComparisonOptions
import Script

## Opt-in external subjects retain their own runtime/version pins. Docker's
## network is enabled only during explicit dependency acquisition.
ComparisonBenchmark := [].{
	Pins : { jiff : Str, rust : Str, go : Str, python : Str, ciso8601 : { version : Str, wheel_url : Str, wheel_sha256 : Str, wheel_filename : Str }, tempo : { revision : Str, version : Str, mix_lock_sha256 : Str, image : Str } }
	Context : { root : Path, work : Path, tempo : Path, pins : Pins, python : Str, environment : List((Str, Str)), chrono : ChronoBenchmark.Context, versions : Dict(Str, Str), affinity : List(U64), options : ComparisonOptions.Options }
	small = ["date_control", "construct", "add_days", "parse", "resolve"]
	libraries = ["roc-time", "chrono", "jiff", "go-time", "datetime", "ciso8601", "tempo"]
	prepare! : ComparisonOptions.Options => Try(Context, _)
	prepare! = |options| {
		if (Script.command("uname").output!(["-s"])?, Script.command("uname").output!(["-m"])?) != ("Linux", "x86_64") {
			return Err(ComparisonRequiresLinuxX64)
		}
		BenchmarkOptions.controls(Path.read_utf8!("tests/benchmark_controls/timing-positive.txt")?)?
		pins : Pins
		pins = Json.parse(Path.read_utf8!("benchmarks/comparison/dependencies.json")?)?
		root = Path.absolute!(".")?
		work = Path.absolute!(".roc-time-tmp/announcement")?
		Path.create_all!(work)?
		tempo = Path.join(work, "tempo")
		# The measured CPython subject deliberately retains the existing 3.12.3
		# pin; independent reference generation uses the contributor's Python.
		python = Script.env_str!("PYTHON_BENCH") ?? "/usr/bin/python3"
		python_version = Script.command(OsStr.from_str(python)).output!(["--version"])?
		go = Script.command("go").output!(["version"])?
		if python_version != "Python ${pins.python}" or go.split_on(" ").get(2)? != pins.go {
			return Err(ComparisonToolchain)
		}
		docker = Script.command("docker").output!(["info", "--format", "{{.ServerVersion}}"])?
		environment = [("PYTHONPATH", "${Path.display(work)}/python")]
		cargo_env = [("CARGO_HOME", "${Path.display(root)}/.roc-time-tmp/chrono-cargo"), ("CARGO_TARGET_DIR", "${Path.display(work)}/jiff-target")]
		available = ComparisonOptions.affinity(Path.read_utf8!("/proc/self/status")?)?
		affinity = match options.cpu {
			[] => available
			[cpu] if available.contains(cpu) => [cpu]
			_ => return Err(CpuOutsideAffinity)
		}
		if options.fetch {
			wheel = Path.join(work, pins.ciso8601.wheel_filename)
			_ = BenchmarkProcess.run!(["curl", "--fail", "--location", "--max-time", "60", "--max-filesize", "16777216", pins.ciso8601.wheel_url, "--output", Path.display(wheel)], root, work, "ciso-download", [], 90000)?
			if hash!(wheel)? != pins.ciso8601.wheel_sha256 {
				return Err(CisoIntegrity)
			}
			_ = BenchmarkProcess.run!(["unzip", "-o", Path.display(wheel), "-d", "${Path.display(work)}/python"], root, work, "ciso-install", [("TMPDIR", Path.display(work))], 300000)?
			if !Path.exists!(tempo)? {
				_ = BenchmarkProcess.run!(["git", "init", Path.display(tempo)], root, work, "tempo-init", [], 300000)?
				_ = BenchmarkProcess.run!(["git", "-C", Path.display(tempo), "remote", "add", "origin", "https://github.com/elixir-tempo/tempo.git"], root, work, "tempo-remote", [], 300000)?
				_ = BenchmarkProcess.run!(["git", "-C", Path.display(tempo), "fetch", "--depth=1", "origin", pins.tempo.revision], root, work, "tempo-fetch", [], 300000)?
				_ = BenchmarkProcess.run!(["git", "-C", Path.display(tempo), "checkout", "--detach", "FETCH_HEAD"], root, work, "tempo-checkout", [], 300000)?
			}
			_ = BenchmarkProcess.run!(["docker", "pull", pins.tempo.image], root, work, "tempo-image", [], 300000)?
			for (label, args) in [("hex", ["mix", "local.hex", "--force"]), ("rebar", ["mix", "local.rebar", "--force"]), ("dependencies", ["mix", "deps.get"]), ("compile", ["mix", "compile"])] {
				_ = BenchmarkProcess.run!(make_docker_prefix(tempo, pins, [], Bool.True).concat(args), root, work, "tempo-${label}", [], 300000)?
			}
			_ = BenchmarkProcess.run!(["cargo", "fetch", "--locked", "--manifest-path", "benchmarks/comparison/rust/Cargo.toml"], root, work, "jiff-fetch", cargo_env, 300000)?
		}
		revision = Script.command("git").output!(["-C", Path.to_os_str(tempo), "rev-parse", "HEAD"])?
		dirty = Script.command("git").output!(["-C", Path.to_os_str(tempo), "diff", "HEAD", "--", "lib", "mix.exs", "mix.lock"])?
		if revision != pins.tempo.revision or !dirty.is_empty() or hash!(Path.join(tempo, "mix.lock"))? != pins.tempo.mix_lock_sha256 {
			return Err(TempoSourceIntegrity)
		}
		ciso = BenchmarkProcess.run!([python, "-c", "import ciso8601; print(ciso8601.__version__)"], root, work, "ciso-version", environment, 300000)?.stdout.trim()
		if ciso != pins.ciso8601.version {
			return Err(CisoVersion)
		}
		chrono_options = BenchmarkOptions.parse(if (options.fetch) ["--smoke", "--fetch"] else ["--smoke"])?
		chrono = ChronoBenchmark.prepare!(chrono_options)?
		if chrono.rust_pin != pins.rust {
			return Err(ComparisonRustVersion)
		}
		# Preserve the preparatory smoke through every Roc/Chrono kernel.
		for mode in BenchmarkOptions.modes {
			for (name, binary) in [("roc-time", chrono.roc_binary), ("chrono", chrono.rust_binary)] {
				output = ChronoBenchmark.execute!(chrono, binary, "benchmark", mode, 1000, 1, 3, "comparison-smoke-${name}-${mode}")?
				_ = BenchmarkOptions.samples(output.stdout, 3, chrono.reference.checksums.get(mode)?)?
			}
		}
		_ = BenchmarkProcess.run!(["cargo", "build", "--offline", "--locked", "--release", "--target", "x86_64-unknown-linux-musl", "--manifest-path", "benchmarks/comparison/rust/Cargo.toml"], root, work, "jiff-build", cargo_env, 300000)?
		_ = BenchmarkProcess.run!(["go", "build", "-trimpath", "-o", "${Path.display(work)}/go-bench", "benchmarks/comparison/go_bench.go"], root, work, "go-build", [("CGO_ENABLED", "0"), ("GOCACHE", "${Path.display(work)}/go-cache")], 300000)?
		Path.copy!("benchmarks/comparison/tempo_bench.exs", Path.join(tempo, "comparison_bench.exs"))?
		elixir = BenchmarkProcess.run!(make_docker_prefix(tempo, pins, [], Bool.False).concat(["elixir", "--version"]), root, work, "elixir-version", [], 300000)?.stdout.trim()
		versions = Dict.from_list([("python", python_version), ("go", go), ("rust", chrono.rustc), ("roc", chrono.roc_version), ("ciso8601", ciso), ("elixir", elixir), ("docker", docker)])
		Ok({ root, work, tempo, pins, python, environment, chrono, versions, affinity, options })
	}
	native : Context -> List((Str, Path))
	native = |context| [("roc-time", context.chrono.roc_binary), ("chrono", context.chrono.rust_binary), ("jiff", Path.join(context.work, "jiff-target/x86_64-unknown-linux-musl/release/roc-time-jiff-benchmark")), ("go-time", Path.join(context.work, "go-bench"))]
	command : Context, Str, List(Str) -> Try(List(Str), [UnknownSubject])
	command = |context, name, args| {
		binary = native(context).keep_if(|(library, _)| library == name)
		base = match binary {
			[(_, path)] => ["env", "--argv0=benchmark", Path.display(path)].concat(args)
			_ => match name {
				subject if ["datetime", "ciso8601"].contains(subject) => [context.python, "benchmarks/comparison/python_bench.py", name].concat(args)
				"tempo" => make_docker_prefix(context.tempo, context.pins, context.options.cpu, Bool.False).concat(["mix", "run", "--no-start", "--no-compile", "--no-deps-check", "comparison_bench.exs"]).concat(args)
				_ => return Err(UnknownSubject)
			}
		}
		match context.options.cpu {
			[cpu] => Ok(["taskset", "--cpu-list", cpu.to_str()].concat(base))
			_ => Ok(base)
		}
	}
	supports : Str, Str -> Bool
	supports = |name, mode| match name {
		"jiff" => small.contains(mode)
		"ciso8601" => ["parse", "parse_only", "end_to_end"].contains(mode)
		"tempo" => small.append("date_to_day").contains(mode)
		_ => BenchmarkOptions.modes.contains(mode)
	}
	docker_prefix : Path, Pins, List(U64), Bool -> List(Str)
	docker_prefix = |tempo, pins, cpu, network| make_docker_prefix(tempo, pins, cpu, network)
}

make_docker_prefix : Path, ComparisonBenchmark.Pins, List(U64), Bool -> List(Str)
make_docker_prefix = |tempo, pins, cpu, network| {
	isolation = if (network) [] else ["--network=none"]
	affinity = match cpu {
		[number] => ["--cpuset-cpus=${number.to_str()}"]
		_ => []
	}
	["docker", "run", "--rm"].concat(isolation).concat(affinity).concat(["-e", "MIX_ENV=prod", "-e", "HEX_HOME=/work/.hex", "-e", "MIX_HOME=/work/.mix", "-e", "ERL_FLAGS=+S 1:1", "-v", "${Path.display(tempo)}:/work", "-w", "/work", pins.tempo.image])
}

hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
