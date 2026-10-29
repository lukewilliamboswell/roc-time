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
	Pins : {
		jiff : Str,
		rust : Str,
		go : Str,
		python : Str,
		ciso8601 : { version : Str, wheel_url : Str, wheel_sha256 : Str, wheel_filename : Str },
		tempo : { revision : Str, version : Str, mix_lock_sha256 : Str, image : Str },
	}
	Context : {
		root : Path,
		work : Path,
		tempo : Path,
		pins : Pins,
		python : Str,
		environment : List((Str, Str)),
		chrono : ChronoBenchmark.Context,
		versions : Dict(Str, Str),
		affinity : List(U64),
		options : ComparisonOptions.Options,
	}
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
		cargo_env = [
			("CARGO_HOME", "${Path.display(root)}/.roc-time-tmp/chrono-cargo"),
			("CARGO_TARGET_DIR", "${Path.display(work)}/jiff-target"),
		]
		available = ComparisonOptions.affinity(Path.read_utf8!("/proc/self/status")?)?
		affinity = match options.cpu {
			[] => available
			[cpu] if available.contains(cpu) => [cpu]
			_ => return Err(CpuOutsideAffinity)
		}
		if options.fetch {
			wheel = Path.join(work, pins.ciso8601.wheel_filename)
			_ = BenchmarkProcess.run!({
				args: [
					"curl",
					"--fail",
					"--location",
					"--max-time",
					"60",
					"--max-filesize",
					"16777216",
					pins.ciso8601.wheel_url,
					"--output",
					Path.display(wheel),
				],
				cwd: root,
				logs: work,
				label: "ciso-download",
				environment: [],
				timeout_ms: 90000,
			})?
			if hash!(wheel)? != pins.ciso8601.wheel_sha256 {
				return Err(CisoIntegrity)
			}
			_ = BenchmarkProcess.run!({
				args: ["unzip", "-o", Path.display(wheel), "-d", "${Path.display(work)}/python"],
				cwd: root,
				logs: work,
				label: "ciso-install",
				environment: [("TMPDIR", Path.display(work))],
				timeout_ms: 300000,
			})?
			if !Path.exists!(tempo)? {
				_ = BenchmarkProcess.run!({
					args: ["git", "init", Path.display(tempo)],
					cwd: root,
					logs: work,
					label: "tempo-init",
					environment: [],
					timeout_ms: 300000,
				})?
				_ = BenchmarkProcess.run!({
					args: [
						"git",
						"-C",
						Path.display(tempo),
						"remote",
						"add",
						"origin",
						"https://github.com/elixir-tempo/tempo.git",
					],
					cwd: root,
					logs: work,
					label: "tempo-remote",
					environment: [],
					timeout_ms: 300000,
				})?
				_ = BenchmarkProcess.run!({
					args: ["git", "-C", Path.display(tempo), "fetch", "--depth=1", "origin", pins.tempo.revision],
					cwd: root,
					logs: work,
					label: "tempo-fetch",
					environment: [],
					timeout_ms: 300000,
				})?
				_ = BenchmarkProcess.run!({
					args: ["git", "-C", Path.display(tempo), "checkout", "--detach", "FETCH_HEAD"],
					cwd: root,
					logs: work,
					label: "tempo-checkout",
					environment: [],
					timeout_ms: 300000,
				})?
			}
			_ = BenchmarkProcess.run!({
				args: ["docker", "pull", pins.tempo.image],
				cwd: root,
				logs: work,
				label: "tempo-image",
				environment: [],
				timeout_ms: 300000,
			})?
			for (label, args) in [
				("hex", ["mix", "local.hex", "--force"]),
				("rebar", ["mix", "local.rebar", "--force"]),
				("dependencies", ["mix", "deps.get"]),
				("compile", ["mix", "compile"]),
			] {
				_ = BenchmarkProcess.run!({
					args: make_docker_prefix({
						tempo,
						pins,
						cpu: [],
						network: AllowNetwork,
					}).concat(args),
					cwd: root,
					logs: work,
					label: "tempo-${label}",
					environment: [],
					timeout_ms: 300000,
				})?
			}
			_ = BenchmarkProcess.run!({
				args: ["cargo", "fetch", "--locked", "--manifest-path", "benchmarks/comparison/rust/Cargo.toml"],
				cwd: root,
				logs: work,
				label: "jiff-fetch",
				environment: cargo_env,
				timeout_ms: 300000,
			})?
		}
		revision = Script.command("git").output!(["-C", Path.to_os_str(tempo), "rev-parse", "HEAD"])?
		dirty = Script.command("git").output!(["-C", Path.to_os_str(tempo), "diff", "HEAD", "--", "lib", "mix.exs", "mix.lock"])?
		if revision != pins.tempo.revision or !dirty.is_empty() or hash!(Path.join(tempo, "mix.lock"))? != pins.tempo.mix_lock_sha256 {
			return Err(TempoSourceIntegrity)
		}
		ciso = BenchmarkProcess.run!({
			args: [python, "-c", "import ciso8601; print(ciso8601.__version__)"],
			cwd: root,
			logs: work,
			label: "ciso-version",
			environment,
			timeout_ms: 300000,
		})?.stdout.trim()
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
				output = ChronoBenchmark.execute!(
					chrono,
					{
						binary,
						argv0: "benchmark",
						mode,
						iterations: 1000,
						warmups: 1,
						samples: 3,
						label: "comparison-smoke-${name}-${mode}",
					},
				)?
				_ = BenchmarkOptions.samples(output.stdout, 3, chrono.reference.checksums.get(mode)?)?
			}
		}
		_ = BenchmarkProcess.run!({
			args: [
				"cargo",
				"build",
				"--offline",
				"--locked",
				"--release",
				"--target",
				"x86_64-unknown-linux-musl",
				"--manifest-path",
				"benchmarks/comparison/rust/Cargo.toml",
			],
			cwd: root,
			logs: work,
			label: "jiff-build",
			environment: cargo_env,
			timeout_ms: 300000,
		})?
		_ = BenchmarkProcess.run!({
			args: [
				"go",
				"build",
				"-trimpath",
				"-o",
				"${Path.display(work)}/go-bench",
				"benchmarks/comparison/go_bench.go",
			],
			cwd: root,
			logs: work,
			label: "go-build",
			environment: [("CGO_ENABLED", "0"), ("GOCACHE", "${Path.display(work)}/go-cache")],
			timeout_ms: 300000,
		})?
		Path.copy!("benchmarks/comparison/tempo_bench.exs", Path.join(tempo, "comparison_bench.exs"))?
		elixir = BenchmarkProcess.run!({
			args: make_docker_prefix({
				tempo,
				pins,
				cpu: [],
				network: Isolated,
			}).concat(["elixir", "--version"]),
			cwd: root,
			logs: work,
			label: "elixir-version",
			environment: [],
			timeout_ms: 300000,
		})?.stdout.trim()
		versions = Dict.from_list([
			("python", python_version),
			("go", go),
			("rust", chrono.rustc),
			("roc", chrono.roc_version),
			("ciso8601", ciso),
			("elixir", elixir),
			("docker", docker),
		])
		Ok({ root, work, tempo, pins, python, environment, chrono, versions, affinity, options })
	}
	native_binaries : Context -> List({ library : Str, binary : Path })
	native_binaries = |context| [
		{ library: "roc-time", binary: context.chrono.roc_binary },
		{ library: "chrono", binary: context.chrono.rust_binary },
		{ library: "jiff", binary: Path.join(context.work, "jiff-target/x86_64-unknown-linux-musl/release/roc-time-jiff-benchmark") },
		{ library: "go-time", binary: Path.join(context.work, "go-bench") },
	]
	command : Context, { library : Str, args : List(Str) } -> Try(List(Str), [UnknownSubject])
	command = |context, { library, args }| {
		binary = native_binaries(context).keep_if(|subject| subject.library == library)
		base = match binary {
			[{ binary: path, .. }] => ["env", "--argv0=benchmark", Path.display(path)].concat(args)
			_ => match library {
				subject if ["datetime", "ciso8601"].contains(subject) => [context.python, "benchmarks/comparison/python_bench.py", library].concat(args)
				"tempo" => make_docker_prefix({
					tempo: context.tempo,
					pins: context.pins,
					cpu: context.options.cpu,
					network: Isolated,
				}).concat(["mix", "run", "--no-start", "--no-compile", "--no-deps-check", "comparison_bench.exs"]).concat(args)
				_ => return Err(UnknownSubject)
			}
		}
		match context.options.cpu {
			[cpu] => Ok(["taskset", "--cpu-list", cpu.to_str()].concat(base))
			_ => Ok(base)
		}
	}
	is_supported_workload : { library : Str, workload : Str } -> Bool
	is_supported_workload = |{ library, workload }| match library {
		"jiff" => small.contains(workload)
		"ciso8601" => ["parse", "parse_only", "end_to_end"].contains(workload)
		"tempo" => small.append("date_to_day").contains(workload)
		_ => BenchmarkOptions.modes.contains(workload)
	}
}

make_docker_prefix : { tempo : Path, pins : ComparisonBenchmark.Pins, cpu : List(U64), network : [AllowNetwork, Isolated] } -> List(Str)
make_docker_prefix = |{ tempo, pins, cpu, network }| {
	isolation = match network {
		AllowNetwork => []
		Isolated => ["--network=none"]
	}
	affinity = match cpu {
		[number] => ["--cpuset-cpus=${number.to_str()}"]
		_ => []
	}
	["docker", "run", "--rm"].concat(isolation).concat(affinity).concat([
		"-e",
		"MIX_ENV=prod",
		"-e",
		"HEX_HOME=/work/.hex",
		"-e",
		"MIX_HOME=/work/.mix",
		"-e",
		"ERL_FLAGS=+S 1:1",
		"-v",
		"${Path.display(tempo)}:/work",
		"-w",
		"/work",
		pins.tempo.image,
	])
}

hash! : Path => Try(Str, _)
hash! = |path| Script.command("sha256sum").output!([Path.to_os_str(path)])?.split_on(" ").first()
