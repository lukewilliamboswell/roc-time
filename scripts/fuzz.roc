#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Files
import src/FuzzEvidence
import src/FuzzOptions
import src/Script

Dependency : { name : Str, version : Str, revision : Str, url : Str, sha256 : Str }

Context : { compiler : Str, version : Str, target : Str, work : Path, dependency : Dependency, host : (Str, Str) }

main! : List(OsStr) => Try({}, _)
main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!({
			label: "usage:",
			message: "blueprint run fuzz -- [--operation build|accept|replay|run|lifecycle|all] [--targets NAME...] [--runs N] [--seconds N] [--seed N]",
		})
	}
	options = FuzzOptions.parse(args.map(OsStr.display))?
	context = prepare!()?
	check_input_admission!(context.work)?
	if options.operation != Lifecycle {
		for name in options.names {
			binary = build!(context, name)?
			if options.operation == Accept {
				_ = run_examples!(
					context,
					{
						name,
						binary,
						action: AcceptBaseline,
					},
				)?
			}
			if [Replay, All].contains(options.operation) {
				_ = run_examples!(
					context,
					{
						name,
						binary,
						action: CheckBaseline,
					},
				)?
				replay!(
					context,
					{
						name,
						binary,
					},
				)?
			}
			if [Run, All].contains(options.operation) {
				campaign!(
					context,
					{
						name,
						binary,
						options,
					},
				)?
			}
		}
	}
	if [Lifecycle, All].contains(options.operation) {
		check_failure_lifecycle!(context)?
		check_baseline_controls!(context)?
	}
	Ok({})
}

prepare! : () => Try(Context, _)
prepare! = || {
	nightly = Script.roc_nightly!()?
	version = nightly.output!(["version"])?
	host = (Script.command("uname").output!(["-s"])?, Script.command("uname").output!(["-m"])?)
	target = match host {
		("Linux", "x86_64") => "x64musl"
		("Darwin", "arm64") => "arm64mac"
		_ => return Script.fail!("unverified fuzz host ${Str.inspect(host)}; no names ran")
	}
	base = Script.env_str!("ROC_TIME_TMPDIR") ?? ".roc-time-tmp"
	work = Path.absolute!(Path.join(Path.utf8(base), "fuzz"))?
	Path.create_all!(work)?
	dependency : Dependency
	dependency = Json.parse(Path.read_utf8!("tests/fuzz/dependency.json")?)?
	context = { compiler: OsStr.display(nightly.program()), version, target, work, dependency, host }
	archive = Path.join(work, "release-${dependency.version}.tar.zst")
	if !Path.exists!(archive)? {
		pending = Path.join(work, "release.download")
		_ = run_command!({
			args: ["curl", "--fail", "--location", "--retry", "2", dependency.url, "--output", Path.display(pending)],
			cwd: Path.utf8("."),
			timeout_ms: 90000,
			expected_exit: 0,
			log: Path.join(work, "download"),
		})?
		if hash_file!(pending)? != dependency.sha256 {
			return Err(PlatformIntegrity)
		}
		Path.rename!(pending, archive)?
	}
	if hash_file!(archive)? != dependency.sha256 {
		return Err(PlatformIntegrity)
	}
	for name in FuzzOptions.names.concat(["lifecycle", "lifecycle_fixed"]) {
		source = Path.read_utf8!(Path.utf8("tests/${name}/main.roc"))?
		urls = source.split_on("fuzz: platform \"").drop_first(1).map(|part| part.split_on("\"").first() ?? "")
		if urls != [dependency.url] {
			return Script.fail!("${name}: expected exact pinned roc-fuzz URL")
		}
	}
	Script.info!({
		label: "FUZZ",
		message: "${version}; LLVM speed --fuzz; target=${target}; roc-fuzz=${dependency.version} (${dependency.revision})",
	})?
	Ok(context)
}

run_command! : { args : List(Str), cwd : Path, timeout_ms : U64, expected_exit : I32, log : Path } => Try(Str, _)
run_command! = |{ args, cwd, timeout_ms, expected_exit, log }| {
	program = args.first().map_err(|_| EmptyCommand)?
	Script.info!({
		label: "+",
		message: Str.join_with(args, " "),
	})?
	result = Cmd.new_str(program).args_str(args.drop_first(1)).cwd(cwd).timeout_ms(timeout_ms).manage_tree(Bool.True).output_limit(16000000).stdout(Capture).stderr(Capture).run!()?
	Path.write_bytes!(Path.utf8("${Path.display(log)}.stdout"), result.stdout_bytes)?
	Path.write_bytes!(Path.utf8("${Path.display(log)}.stderr"), result.stderr_bytes)?
	output = "${Str.from_utf8(result.stdout_bytes)?}${Str.from_utf8(result.stderr_bytes)?}"
	if result.status != Exited(expected_exit) {
		Stderr.line!(output)?
		return Err(UnexpectedExit(result.status))
	}
	Ok(output)
}

hash_file! : Path => Try(Str, _)
hash_file! = |path| {
	output = Script.command("sha256sum").output!([Path.to_os_str(path)])?
	match output.split_on(" ") {
		[digest, ..] => Ok(digest)
		_ => Err(HashOutput)
	}
}

build! : Context, Str => Try(Path, _)
build! = |context, name| {
	source = "tests/${name}/main.roc"
	_ = run_command!({
		args: [context.compiler, "check", source],
		cwd: Path.utf8("."),
		timeout_ms: 300000,
		expected_exit: 0,
		log: Path.join(context.work, "${name}-check"),
	})?
	binary = Path.join(context.work, name)
	_ = run_command!({
		args: [context.compiler, "build", "--fuzz", "--opt=speed", "--target=${context.target}", source, "--output=${Path.display(binary)}"],
		cwd: Path.utf8("."),
		timeout_ms: 300000,
		expected_exit: 0,
		log: Path.join(context.work, "${name}-build"),
	})?
	Ok(binary)
}

read_corpus! : Path => Try(List(Path), _)
read_corpus! = |directory| {
	entries = Files.sort_paths(Path.list!(directory)?)
	if entries.is_empty() or entries.len() > 10000 {
		return Err(CorpusSize)
	}
	for entry in entries {
		if Path.is_sym_link!(entry)? or Path.type!(entry)? != IsFile or Path.size_in_bytes!(entry)? > 256 {
			return Err(CorpusInput)
		}
	}
	Ok(entries)
}

check_input_admission! : Path => Try({}, _)
check_input_admission! = |parent| {
	directory = Env.create_temp_dir_in!(parent, "admission-")?
	match read_corpus!(directory) {
		Err(CorpusSize) => {}
		_ => return Err(AdmissionControl)
	}
	file = Path.join(directory, "boundary")
	Path.write_bytes!(file, List.repeat(0.U8, 256))?
	_ = read_corpus!(directory)?
	Path.write_bytes!(file, List.repeat(0.U8, 257))?
	match read_corpus!(directory) {
		Err(CorpusInput) => {}
		_ => return Err(AdmissionControl)
	}
	Path.delete!(file)?
	Path.create_all!(Path.join(directory, "not-a-file"))?
	match read_corpus!(directory) {
		Err(CorpusInput) => {}
		_ => return Err(AdmissionControl)
	}
	Path.delete_all!(directory)?
	Script.info!({
		label: "PASS",
		message: "corpus admission: empty, 256/257-byte boundary and directory controls",
	})
}

replay! : Context, { name : Str, binary : Path } => Try({}, _)
replay! = |context, { name, binary }| {
	directory = Path.utf8("tests/fuzz/corpus/${name}")
	retained = if (Path.exists!(directory)?) read_corpus!(directory)? else []
	for raw in retained {
		report_dir = Env.create_temp_dir_in!(context.work, "${name}-replay-")?
		_ = run_command!({
			args: [Path.display(binary), "replay", Path.display(Path.absolute!(raw)?), "--report-dir=${Path.display(report_dir)}"],
			cwd: context.work,
			timeout_ms: 10000,
			expected_exit: 0,
			log: Path.join(context.work, "${name}-replay-${Files.name(raw)}"),
		})?
		validate_report!(
			context,
			{
				directory: report_dir,
				baseline: NotChecked,
				exploration: NotRequested,
			},
		)?
		replay : FuzzEvidence.Report
		replay = Json.parse(Path.read_utf8!(Path.join(report_dir, "report.json"))?)?
		if replay.examples.len() != 1 or replay.examples.first()?.input_sha256 != hash_file!(raw)? {
			return Err(MissingReplayEvidence)
		}
	}
	Script.info!({
		label: "PASS",
		message: "${name}: curated replay",
	})
}

campaign! : Context, { name : Str, binary : Path, options : FuzzOptions.Options } => Try({}, _)
campaign! = |context, { name, binary, options }| {
	sessions = Path.join(context.work, "campaigns")
	Path.create_all!(sessions)?
	session = Env.create_temp_dir_in!(sessions, name)?
	corpus = Path.join(session, "corpus")
	Path.create_all!(corpus)?
	persistent = Path.join(context.work, "persistent/${name}")
	if Path.exists!(persistent)? {
		for raw in read_corpus!(persistent)? {
			Path.copy!(raw, Path.join(corpus, Files.name(raw)))?
		}
	}
	examples_report = run_examples!(
		context,
		{
			name,
			binary,
			action: CheckBaseline,
		},
	)?
	prepared : { examples : List({ name : Str, input_path : Str, input_sha256 : Str }) }
	prepared = Json.parse(Path.read_utf8!(Path.join(examples_report, "report.json"))?)?
	for (example, index) in prepared.examples.map_with_index(|example, index| (example, index)) {
		raw = Path.utf8(example.input_path)
		if Path.size_in_bytes!(raw)? > 256 or hash_file!(raw)? != example.input_sha256 {
			return Err(PreparedSeedIntegrity)
		}
		destination = Path.join(corpus, "named-${index.to_str()}")
		if Path.exists!(destination)? {
			Path.delete!(destination)?
		}
		Path.copy!(raw, destination)?
	}
	var $source_hashes = []
	for raw in Files.direct_roc_files!(Path.utf8("tests/${name}"))?.concat(Files.direct_roc_files!("package")?) {
		$source_hashes = $source_hashes.append((Path.display(raw), hash_file!(raw)?))
	}
	var $corpus_hashes = []
	for raw in read_corpus!(corpus)? {
		$corpus_hashes = $corpus_hashes.append((Files.name(raw), hash_file!(raw)?))
	}
	metadata = {
		compiler: context.version,
		platform_info: context.dependency,
		host: [context.host.0, context.host.1],
		runner_sha256: hash_file!("scripts/fuzz.roc")?,
		options_sha256: hash_file!("scripts/src/FuzzOptions.roc")?,
		target: context.target,
		backend: "LLVM speed --fuzz",
		runs: options.runs,
		seconds: options.seconds,
		seed: options.seed,
		max_input_bytes: 256.U64,
		rss_limit_mb: 256.U64,
		input_timeout_seconds: 2.U64,
		sources_sha256: Dict.from_list($source_hashes),
		corpus_sha256: Dict.from_list($corpus_hashes),
	}
	Path.write_utf8!(Path.join(session, "metadata.json"), Json.to_str(metadata))?
	# The engine's finite budget is separate from the process-tree deadline.
	# Argument admission bounds this addition and multiplication within U64.
	report_dir = Path.join(session, "quality")
	baseline = Path.absolute!("tests/fuzz/baselines/${name}.json")?
	_ = run_command!({
		args: [Path.display(binary), "run", Path.display(corpus), "--report-dir=${Path.display(report_dir)}", "--baseline=${Path.display(baseline)}", "--profile=speed", "--source-revision=${Script.command("git").output!(["rev-parse", "HEAD"])?}", "--roc-version=${context.version}", "--platform-release=${context.dependency.version}", "--platform-sha256=${context.dependency.sha256}", "--runs=${options.runs.to_str()}", "--time=${options.seconds.to_str()}", "--seed=${options.seed.to_str()}", "--max-input-size=256", "--memory-limit=256", "--timeout=2"],
		cwd: session,
		timeout_ms: (options.seconds + 30) * 1000,
		expected_exit: 0,
		log: Path.join(session, "run"),
	})?
	validate_report!(
		context,
		{
			directory: report_dir,
			baseline: Matched,
			exploration: RequireAcceptedInput,
		},
	)?
	_ = read_corpus!(corpus)?
	if Path.exists!(persistent)? {
		Path.delete_all!(persistent)?
	}
	Path.create_all!(Path.join(context.work, "persistent"))?
	Path.copy_dir!(corpus, persistent)?
	Script.info!({
		label: "PASS",
		message: "${name}: bounded search; evidence ${Path.display(session)}",
	})
}

check_failure_lifecycle! : Context => Try({}, _)
check_failure_lifecycle! = |context| {
	bad = build!(context, "lifecycle")?
	fixed = build!(context, "lifecycle_fixed")?
	session = Env.create_temp_dir_in!(context.work, "lifecycle-")?
	corpus = Path.join(session, "corpus")
	Path.create_all!(corpus)?
	Path.write_bytes!(Path.join(corpus, "trigger"), "before*after".to_utf8())?
	failed = run_command!({
		args: [Path.display(bad), "run", Path.display(corpus), "--runs=100", "--time=1", "--seed=1", "--max-input-size=32", "--memory-limit=256", "--timeout=2", "--report-dir=${Path.display(Path.join(session, "quality"))}"],
		cwd: session,
		timeout_ms: 15000,
		expected_exit: 1,
		log: Path.join(session, "failure"),
	})?
	native_log = Path.read_utf8!(Path.join(session, "quality/run.log"))?
	if !failed.contains("finding") or !native_log.contains("intentional lifecycle defect") {
		return Err(UnrelatedLifecycleFailure)
	}
	finding : { outcome : Str, exploration : { termination : { exit_code : U64 }, original_input_complete : Bool } }
	finding = Json.parse(Path.read_utf8!(Path.join(session, "quality/report.json"))?)?
	if finding.outcome != "finding" or finding.exploration.termination.exit_code != 77 or !finding.exploration.original_input_complete {
		return Err(MissingReproducer)
	}
	raw = Path.join(session, "quality/original-input.bin")
	shown = run_command!({
		args: [Path.display(bad), "show", Path.display(raw)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 0,
		log: Path.join(session, "show"),
	})?
	if !shown.contains("42") {
		return Err(MissingTrigger)
	}
	_ = run_command!({
		args: [Path.display(bad), "replay", Path.display(raw)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 1,
		log: Path.join(session, "replay"),
	})?
	match run_command!({
		args: [Path.display(bad), "replay", Path.display(raw)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 0,
		log: Path.join(session, "gate-control"),
	}) {
		Err(UnexpectedExit(Exited(1))) => {}
		_ => return Err(BrokenFailureGate)
	}
	minimized = Path.join(session, "minimized")
	_ = run_command!({
		args: [Path.display(bad), "minimize", Path.display(raw), Path.display(minimized)],
		cwd: session,
		timeout_ms: 30000,
		expected_exit: 0,
		log: Path.join(session, "minimize"),
	})?
	if Path.read_bytes!(minimized)? != "*".to_utf8() {
		return Err(UnexpectedMinimization)
	}
	_ = run_command!({
		args: [Path.display(bad), "show", Path.display(minimized)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 0,
		log: Path.join(session, "show-minimized"),
	})?
	_ = run_command!({
		args: [Path.display(bad), "replay", Path.display(minimized)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 1,
		log: Path.join(session, "replay-minimized"),
	})?
	_ = run_command!({
		args: [Path.display(fixed), "replay", Path.display(minimized)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 0,
		log: Path.join(session, "fixed"),
	})?
	regression = Path.absolute!("tests/fuzz/corpus/lifecycle_fixed/byte-42")?
	_ = run_command!({
		args: [Path.display(fixed), "replay", Path.display(regression)],
		cwd: session,
		timeout_ms: 10000,
		expected_exit: 0,
		log: Path.join(session, "regression"),
	})?
	Script.info!({
		label: "PASS",
		message: "failure lifecycle: saved/show/replay/minimize, supervisor exit 1 / engine exit 77, fixed regression; ${Path.display(session)}",
	})
}

run_examples! : Context, { name : Str, binary : Path, action : [AcceptBaseline, CheckBaseline] } => Try(Path, _)
run_examples! = |context, { name, binary, action }| {
	report_dir = Env.create_temp_dir_in!(context.work, "${name}-examples-")?
	baseline = Path.absolute!("tests/fuzz/baselines/${name}.json")?
	_ = run_command!({
		args: [
			Path.display(binary),
			match action {
				AcceptBaseline => "accept"
				CheckBaseline => "check"
			},
			"--baseline=${Path.display(baseline)}",
			"--profile=speed",
			"--report-dir=${Path.display(report_dir)}",
		],
		cwd: context.work,
		timeout_ms: 60000,
		expected_exit: 0,
		log: Path.join(report_dir, "supervisor"),
	})?
	validate_report!(
		context,
		{
			directory: report_dir,
			baseline: match action {
				AcceptBaseline => Accepted
				CheckBaseline => Matched
			},
			exploration: NotRequested,
		},
	)?
	Script.info!({
		label: "PASS",
		message: "${name}: named examples and ${
			match action {
				AcceptBaseline => "explicitly accepted"
				CheckBaseline => "matched"
			}
		} allocation baseline; ${Path.display(report_dir)}",
	})?
	Ok(report_dir)
}

validate_report! : Context, { directory : Path, baseline : FuzzEvidence.Baseline, exploration : FuzzEvidence.Exploration } => Try({}, _)
validate_report! = |context, { directory, baseline, exploration }| {
	report : FuzzEvidence.Report
	report = Json.parse(Path.read_utf8!(Path.join(directory, "report.json"))?)?
	FuzzEvidence.validate(report, { host: context.target, baseline, exploration })
}

check_baseline_controls! : Context => Try({}, _)
check_baseline_controls! = |context| {
	binary = build!(context, "clock")?
	work = Env.create_temp_dir_in!(context.work, "baseline-controls-")?
	changed = Path.join(work, "changed.json")
	source = Path.read_utf8!("tests/fuzz/baselines/clock.json")?
	edited = Str.join_with(source.split_on("\"revision\":\"1\""), "\"revision\":\"control\"")
	if edited == source {
		return Err(BaselineControlFixture)
	}
	Path.write_utf8!(changed, edited)?
	changed_report = Path.join(work, "changed")
	_ = run_command!({
		args: [Path.display(binary), "check", "--baseline=${Path.display(changed)}", "--profile=speed", "--report-dir=${Path.display(changed_report)}"],
		cwd: context.work,
		timeout_ms: 30000,
		expected_exit: 1,
		log: Path.join(work, "changed-supervisor"),
	})?
	result : { outcome : Str, baseline_status : Str, exploration : { status : Str } }
	result = Json.parse(Path.read_utf8!(Path.join(changed_report, "report.json"))?)?
	if result.outcome != "baseline_changed" or result.baseline_status != "changed" or result.exploration.status != "skipped" {
		return Err(BrokenBaselineGate)
	}
	missing_report = Path.join(work, "missing")
	_ = run_command!({
		args: [Path.display(binary), "check", "--baseline=${Path.display(Path.join(work, "missing.json"))}", "--profile=speed", "--report-dir=${Path.display(missing_report)}"],
		cwd: context.work,
		timeout_ms: 30000,
		expected_exit: 0,
		log: Path.join(work, "missing-supervisor"),
	})?
	match validate_report!(
		context,
		{
			directory: missing_report,
			baseline: Matched,
			exploration: NotRequested,
		},
	) {
		Err(FuzzEvidence) => {}
		_ => return Err(BrokenBaselineGate)
	}
	Script.info!({
		label: "PASS",
		message: "changed baseline fails and skips exploration; unbaselined success is rejected by repository policy",
	})
}
