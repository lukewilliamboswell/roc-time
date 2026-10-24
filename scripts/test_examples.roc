#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.Tcp
import cli.Utc
import src/Files
import src/Release
import src/Script
import src/StaticChecks
import src/Text

App : { name : Str, directory : Path, expected : [Golden(Path), Clock, Unchecked] }

Route : { path : Str, body : [Bytes(List(U8)), NotFound] }

Server : [NoServer, Server({ listener : Tcp.Listener, routes : List(Route) })]

main! = |_args| {
	# Check, run and build example applications and compare their output with
	# recorded expectations. Everything here uses the package compiler.
	#
	# By default the working tree's examples run in place against the working
	# tree's packages, along with the deterministic check applications in tests/.
	#
	# EXAMPLES_ARCHIVE names a roc-time-examples-<version>.zip, which is run
	# unchanged with its own expectations: against the published URLs its headers
	# name, or, when BUNDLE_DIR is set, against that directory's candidate
	# bundles served on loopback, followed by the bundle rejection cases.
	roc_nightly = Script.roc_nightly!()?
	Env.with_temp_dir!(
		|temporary|
			match Script.env_str!("EXAMPLES_ARCHIVE") {
				Ok(archive) => test_archive!(roc_nightly, Path.utf8(archive), temporary)
				Err(NotSet) => test_working_tree!(roc_nightly, temporary)
				Err(err) => Err(err)
			},
	)
}

test_working_tree! = |roc_nightly, temporary| {
	Script.section!("EXAMPLES")?
	examples = applications!("examples", "tests/examples")?
	for example in examples {
		if required_expectations.contains(example.name) and example.expected == Unchecked {
			return Script.fail!("missing required output fixture: tests/examples/${example.name}.txt")
		}
	}

	# Two check applications drive the exact pure module of a public example.
	# Roc imports cannot leave an application's directory, so stage a copy with
	# that module beside it and the package named by absolute path.
	Script.section!("CHECK APPLICATIONS")?
	core = Path.display(Path.absolute!("package/main.roc")?)
	var $checks = []
	for name in ["schedule_definition_checks", "utc_cancellations_checks"] {
		$checks = $checks.append({ name, directory: Path.join("tests", name), expected: Golden(Path.join("tests/examples", "${name}.txt")) })
	}
	for (name, file) in [("clock_deadline_checks", "examples/clock_deadline/Deadline.roc"), ("invoice_report_checks", "examples/invoice_report/InvoiceReport.roc")] {
		directory = Path.join(Path.join(temporary, "staged"), name)
		Path.create_all!(Path.join(temporary, "staged"))?
		Path.copy_dir!(Path.join("tests", name), directory)?
		Path.copy!(file, Path.join(directory, Files.name(file)))?
		main = Path.join(directory, "main.roc")
		Path.write_utf8!(main, Text.rewrite_dependency(Path.read_utf8!(main)?, "time", core)?)?
		$checks = $checks.append({ name, directory, expected: Golden(Path.join("tests/examples", "${name}.txt")) })
	}

	all = examples.concat($checks)
	for example in all {
		run_application!(roc_nightly, example, [], [], NoServer, temporary)?
	}
	Stdout.line!("\nAll ${all.len().to_str()} applications passed in the working tree.")
}

test_archive! = |roc_nightly, archive, temporary| {
	# A published archive is immutable: its sources are never rewritten or
	# reformatted, and its own expected/ directory describes its release.
	unpacked = Path.join(temporary, "archive")
	Cmd.new("unzip").args(["-q", Path.to_os_str(Path.absolute!(archive)?), "-d", Path.to_os_str(unpacked)]).exec_cmd!()?
	root = match Path.list!(unpacked)? {
		[only] => only
		_ => return Script.fail!("${Path.display(archive)} must contain exactly one top-level directory")
	}
	examples = applications!(Path.join(root, "examples"), Path.join(root, "expected"))?
	if examples.is_empty() {
		return Script.fail!("${Path.display(archive)} contains no applications")
	}
	sources = examples.map_try!(|example| Path.read_utf8!(Path.join(example.directory, "main.roc")))?
	core_url = match unique(sources.map(|source| Text.dependency_values(source, "time"))) {
		[[url]] => url
		_ => return Script.fail!("every archived application must name the same single time bundle URL")
	}
	zones_url = match unique(sources.map(|source| Text.dependency_values(source, "zones")).keep_if(|values| values != [])) {
		[[url]] => url
		_ => return Script.fail!("archived applications must agree on one zones bundle URL")
	}
	Script.info!("ARCHIVE", "time ${core_url}")?
	Script.info!("ARCHIVE", "zones ${zones_url}")?

	match Script.env_str!("BUNDLE_DIR") {
		Err(NotSet) => {
			Script.section!("PUBLISHED EXAMPLES")?
			for example in examples {
				run_application!(roc_nightly, example, [], [], NoServer, temporary)?
			}
			Stdout.line!("\nAll ${examples.len().to_str()} archived applications passed against their published packages.")
		}
		Ok(directory) => {
			# The declared URLs are not published yet, so serve the candidate
			# bundles on loopback and load them in place of those URLs. A fresh
			# package cache makes each acquisition cold.
			bundle_dir = Path.utf8(directory)
			bundles = Release.parse_manifest(Path.read_utf8!(Path.join(bundle_dir, "roc-time-bundles.json"))?)?
			if !core_url.ends_with("/${bundles.core.artifact_file}") or !zones_url.ends_with("/${bundles.zones.artifact_file}") {
				return Script.fail!("the archive does not name the bundles in ${directory}")
			}
			core = Path.read_bytes!(Path.join(Path.join(bundle_dir, "core"), bundles.core.artifact_file))?
			zones = Path.read_bytes!(Path.join(Path.join(bundle_dir, "zones"), bundles.zones.artifact_file))?
			listener = Tcp.listen!("127.0.0.1", 0, 5_000)?
			base = "http://127.0.0.1:${listener.local_port!()?.to_str()}"
			routes = [
				{ path: "/candidate/${bundles.core.artifact_file}", body: Bytes(core) },
				{ path: "/candidate/${bundles.zones.artifact_file}", body: Bytes(zones) },
				{ path: "/missing/${bundles.core.artifact_file}", body: NotFound },
				{ path: "/corrupt/${bundles.core.artifact_file}", body: Bytes(Str.to_utf8("deliberately malformed release archive\n")) },
			]
			server = Server({ listener, routes })
			local_core = "${base}/candidate/${bundles.core.artifact_file}"
			local_zones = "${base}/candidate/${bundles.zones.artifact_file}"
			# A replacement nothing declares is an error, so name the zones
			# bundle only for applications that depend on it.
			replace = |zoned, core_target, zones_target|
				["--replace-dep", core_url, core_target]
					.concat(if (zoned) ["--replace-dep", zones_url, zones_target] else [])
					.map(OsStr.from_str)

			Script.section!("ARCHIVE SOURCES")?
			compare_with_tree!(examples)?

			Script.section!("CANDIDATE BUNDLES")?
			cache = Path.join(temporary, "cache")
			Path.create_all!(cache)?
			for example in examples {
				zoned = !Text.dependency_values(Path.read_utf8!(Path.join(example.directory, "main.roc"))?, "zones").is_empty()
				run_application!(roc_nightly, example, replace(zoned, local_core, local_zones), [("XDG_CACHE_HOME", Path.to_os_str(cache))], server, temporary)?
			}

			Script.section!("REJECTIONS")?
			zoned = match examples.find_first(|example| example.name == "staffing") {
				Ok(found) => found
				Err(_) => return Script.fail!("the staffing application is needed for the rejection cases")
			}
			rejections = [
				{ name: "missing", diagnostic: "package download failed", args: replace(Bool.True, "${base}/missing/${bundles.core.artifact_file}", local_zones) },
				{ name: "corrupt", diagnostic: "package download failed", args: replace(Bool.True, "${base}/corrupt/${bundles.core.artifact_file}", local_zones) },
				{ name: "swapped", diagnostic: "package module is private", args: replace(Bool.True, local_zones, local_core) },
			]
			for rejection in rejections {
				fresh = Path.join(temporary, "cache-${rejection.name}")
				Path.create_all!(fresh)?
				command = roc_nightly
					.cmd(["check", "main.roc", "--no-cache"].concat(rejection.args))
					.cwd(zoned.directory)
					.env("XDG_CACHE_HOME", Path.to_os_str(fresh))
					.stdout(Capture)
					.stderr(Capture)
				output = wait_serving!(command.spawn!().map_err(|err| SpawnFailed(err))?, server)?
				report = "${Str.from_utf8_lossy(output.stdout_bytes)}${Str.from_utf8_lossy(output.stderr_bytes)}"
				match output.status {
					Exited(0) => return Script.fail!("${rejection.name} bundle was accepted")
					_ if !report.contains(rejection.diagnostic) =>
						return Script.fail!("${rejection.name} bundle failed without \"${rejection.diagnostic}\":\n${report}")
					_ => Script.info!("PASS", "rejected ${rejection.name} bundle: ${rejection.diagnostic}")?
				}
			}
			listener.close!()?
			Stdout.line!("\nAll ${examples.len().to_str()} archived applications passed against the candidate bundles.")
		}
		Err(err) => Err(err)
	}
}

## A candidate archive is built from this working tree, so it must hold the
## same applications and files, differing only in the package dependency
## lines of each `main.roc`.
compare_with_tree! = |archived| {
	tree = applications!("examples", "tests/examples")?
	if archived.map(|example| example.name) != tree.map(|example| example.name) {
		return Script.fail!("the archive and examples/ hold different applications")
	}
	var $rewritten = 0
	var $files = 0.U64
	for example in archived {
		ours = Files.direct_roc_files!(Path.join("examples", example.name))?
		theirs = Files.direct_roc_files!(example.directory)?
		if ours.map(Files.name) != theirs.map(Files.name) {
			return Script.fail!("${example.name}: the archive holds different files")
		}
		for file in ours {
			name = Files.name(file)
			source = Path.read_utf8!(file)?
			copy = Path.read_utf8!(Path.join(example.directory, name))?
			$files = $files + 1
			if name == "main.roc" {
				match Release.dependency_only_changes(source, copy) {
					Ok(count) => {
						$rewritten = $rewritten + count
					}
					Err(_) => return Script.fail!("${example.name}/main.roc differs beyond its package dependency lines")
				}
			} else if source != copy {
				return Script.fail!("${example.name}/${name} differs from the working tree")
			}
		}
	}
	Script.info!("PASS", "${$files.to_str()} archived files match the working tree; only ${$rewritten.to_str()} package dependency lines differ")
}

## Applications under `directory`, each a folder with a `main.roc`, paired
## with the expectation of the same name under `expected`.
applications! : Path, Path => Try(List(App), _)
applications! = |directory, expected| {
	names = Text.sort_names(Path.list!(directory)?.keep_if_try!(|path| Path.is_dir!(path))?.map(Files.name))
	names.map_try!(
		|name| {
			folder = Path.join(directory, name)
			if !Path.is_file!(Path.join(folder, "main.roc"))? {
				return Script.fail!("${Path.display(folder)} has no main.roc")
			}
			golden = Path.join(expected, "${name}.txt")
			Ok({
				name,
				directory: folder,
				expected: if (name == "clock_deadline") Clock else if (Path.exists!(golden)?) Golden(golden) else Unchecked,
			})
		},
	)
}

run_application! = |roc_nightly, example, extra, envs, server, temporary| {
	Stdout.line!("APP ${example.name}")?
	roc = |args| roc_nightly.cmd(args.concat(extra)).cwd(example.directory).envs(envs)
	_ = step!(roc(["check", "main.roc", "--no-cache"]), server)?

	before = now!()
	interpreted = step!(roc(["main.roc", "--no-cache"]).stdout(Capture), server)?
	verify!(example, "interpreted", interpreted.stdout_bytes, before, now!())?

	build_dir = Path.join(temporary, "build")
	empty = Path.join(temporary, "empty-cwd")
	Path.create_all!(build_dir)?
	Path.create_all!(empty)?
	binary = Path.join(build_dir, example.name)
	_ = step!(roc(["build", "main.roc", "--opt=dev", OsStr.from_str("--output=${Path.display(binary)}"), "--no-cache"]), server)?
	started = now!()
	native = step!(Cmd.new(Path.to_os_str(binary)).cwd(empty).stdout(Capture), NoServer)?
	verify!(example, "native", native.stdout_bytes, started, now!())
}

## Run a command to completion, serving loopback requests while it runs.
step! = |command, server| {
	output = wait_serving!(command.spawn!().map_err(|err| SpawnFailed(err))?, server)?
	match output.status {
		Exited(0) => Ok(output)
		Exited(code) => Err(StepExited(code))
		Signaled(signal) => Err(StepSignaled(signal))
	}
}

verify! = |example, mode, bytes, before, after| {
	actual = Str.from_utf8(bytes).map_err(|_| OutputNotUtf8(example.name))?
	match example.expected {
		Clock => Release.clock_problem(actual, before, after)
		Golden(path) =>
			if actual == Path.read_utf8!(path)? {
				Ok({})
			} else {
				Script.fail!("unexpected ${mode} output from ${example.name}:\n${actual}")
			}
		Unchecked => Ok({})
	}
}

## The current UTC time as `YYYY-MM-DDTHH:MM:SS`.
now! = || Str.from_utf8_lossy(Str.to_utf8(Utc.to_iso_8601(Utc.now!())).take_first(19))

wait_serving! : Cmd.Child, Server => Try(Cmd.RunOutput, _)
wait_serving! = |child, server|
	match server {
		NoServer => child.wait!().map_err(|err| WaitFailed(err))
		Server({ listener, routes }) =>
		# The compiler fetches bundles while it runs. Poll so this process can
		# answer those requests and watch for the child's exit without threads.
			match child.try_wait!().map_err(|err| WaitFailed(err))? {
				[output] => Ok(output)
				[_, _, ..] => Err(UnexpectedWaitResult)
				[] =>
					match listener.accept!(100) {
						Ok(stream) => {
							request = stream.read_line!(65_536, 5_000)?
							match routes.find_first(|route| request.starts_with("GET ${route.path} ")) {
								Ok({ body: Bytes(bytes), .. }) => {
									stream.write_utf8!(http_headers("200 OK", bytes.len()), 5_000)?
									stream.write!(bytes, 30_000)?
								}
								_ => stream.write_utf8!(http_headers("404 Not Found", 0), 5_000)?
							}
							wait_serving!(child, server)
						}
						Err(TcpListenErr(TimedOut)) => wait_serving!(child, server)
						Err(err) => Err(ServeFailed(err))
					}
			}
	}

http_headers : Str, U64 -> Str
http_headers = |status, content_length|
	# HTTP requires CRLF separators, which a multiline string would not produce.
	Str.join_with(
		[
			"HTTP/1.1 ${status}",
			"Content-Type: application/octet-stream",
			"Content-Length: ${content_length.to_str()}",
			"Connection: close",
			"",
			"",
		],
		"\r\n",
	)

unique = |values| {
	var $seen = []
	for value in values {
		if !$seen.contains(value) {
			$seen = $seen.append(value)
		}
	}
	$seen
}

# Applications whose output must be compared; adding one without a fixture fails.
required_expectations = ["archive_intervals", "booking_exchange", "archive_search", "staffing", "invoice", "upcoming_meetings", "appointment_display", "zoned_appointment", "invoice_report", "schedule_exchange", "meeting_exchange"]

# Keep the static rule and this harness on the same package paths.
expect StaticChecks.core_path == "../../package/main.roc"
