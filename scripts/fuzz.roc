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

main! = |args| {
	if args.map(OsStr.display) == ["--help"] {
		return Script.info!("usage:", "blueprint run fuzz -- [--operation build|accept|replay|run|lifecycle|all] [--targets NAME...] [--runs N] [--seconds N] [--seed N]")
	}
	options = FuzzOptions.parse(args.map(OsStr.display))?
	context = prepare!()?
	check_input_admission!(context.work)?
	if options.operation != "lifecycle" {
		for name in options.names {
			binary = build!(context, name)?
			if options.operation == "accept" {
				examples!(context, name, binary, Bool.True)?
			}
			if ["replay", "all"].contains(options.operation) {
				examples!(context, name, binary, Bool.False)?
				replay!(context, name, binary)?
			}
			if ["run", "all"].contains(options.operation) {
				campaign!(context, name, binary, options)?
			}
		}
	}
	if ["lifecycle", "all"].contains(options.operation) {
		lifecycle!(context)?
		baseline_controls!(context)?
	}
	Ok({})
}

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
		_ = command!(["curl", "--fail", "--location", "--retry", "2", dependency.url, "--output", Path.display(pending)], Path.utf8("."), 90000, 0, Path.join(work, "download"))?
		if hash!(pending)? != dependency.sha256 {
			return Err(PlatformIntegrity)
		}
		Path.rename!(pending, archive)?
	}
	if hash!(archive)? != dependency.sha256 {
		return Err(PlatformIntegrity)
	}
	for name in FuzzOptions.names.concat(["lifecycle", "lifecycle_fixed"]) {
		source = Path.read_utf8!(Path.utf8("tests/${name}/main.roc"))?
		urls = source.split_on("fuzz: platform \"").drop_first(1).map(|part| part.split_on("\"").first() ?? "")
		if urls != [dependency.url] {
			return Script.fail!("${name}: expected exact pinned roc-fuzz URL")
		}
	}
	Script.info!("FUZZ", "${version}; LLVM speed --fuzz; target=${target}; roc-fuzz=${dependency.version} (${dependency.revision})")?
	Ok(context)
}

command! = |args, cwd, timeout, expected, log| {
	program = args.first().map_err(|_| EmptyCommand)?
	Script.info!("+", Str.join_with(args, " "))?
	result = Cmd.new_str(program).args_str(args.drop_first(1)).cwd(cwd).timeout_ms(timeout).manage_tree(Bool.True).output_limit(16000000).stdout(Capture).stderr(Capture).run!()?
	Path.write_bytes!(Path.utf8("${Path.display(log)}.stdout"), result.stdout_bytes)?
	Path.write_bytes!(Path.utf8("${Path.display(log)}.stderr"), result.stderr_bytes)?
	output = "${Str.from_utf8(result.stdout_bytes)?}${Str.from_utf8(result.stderr_bytes)?}"
	if result.status != Exited(expected) {
		Stderr.line!(output)?
		return Err(UnexpectedExit(result.status))
	}
	Ok(output)
}

hash! = |path| {
	output = Script.command("sha256sum").output!([Path.to_os_str(path)])?
	match output.split_on(" ") {
		[digest, ..] => Ok(digest)
		_ => Err(HashOutput)
	}
}

build! = |context, name| {
	source = "tests/${name}/main.roc"
	_ = command!([context.compiler, "check", source], Path.utf8("."), 300000, 0, Path.join(context.work, "${name}-check"))?
	binary = Path.join(context.work, name)
	_ = command!([context.compiler, "build", "--fuzz", "--opt=speed", "--target=${context.target}", source, "--output=${Path.display(binary)}"], Path.utf8("."), 300000, 0, Path.join(context.work, "${name}-build"))?
	Ok(binary)
}

inputs! = |directory| {
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

check_input_admission! = |parent| {
	directory = Env.create_temp_dir_in!(parent, "admission-")?
	match inputs!(directory) {
		Err(CorpusSize) => {}
		_ => return Err(AdmissionControl)
	}
	file = Path.join(directory, "boundary")
	Path.write_bytes!(file, List.repeat(0.U8, 256))?
	_ = inputs!(directory)?
	Path.write_bytes!(file, List.repeat(0.U8, 257))?
	match inputs!(directory) {
		Err(CorpusInput) => {}
		_ => return Err(AdmissionControl)
	}
	Path.delete!(file)?
	Path.create_all!(Path.join(directory, "not-a-file"))?
	match inputs!(directory) {
		Err(CorpusInput) => {}
		_ => return Err(AdmissionControl)
	}
	Path.delete_all!(directory)?
	Script.info!("PASS", "corpus admission: empty, 256/257-byte boundary and directory controls")
}

replay! = |context, name, binary| {
	for raw in inputs!(Path.utf8("tests/fuzz/corpus/${name}"))? {
		report_dir = Env.create_temp_dir_in!(context.work, "${name}-replay-")?
		_ = command!([Path.display(binary), "replay", Path.display(Path.absolute!(raw)?), "--report-dir=${Path.display(report_dir)}"], context.work, 10000, 0, Path.join(context.work, "${name}-replay-${Files.name(raw)}"))?
		validate_report!(context, report_dir, "not_checked", Bool.False)?
		replay : FuzzEvidence.Report
		replay = Json.parse(Path.read_utf8!(Path.join(report_dir, "report.json"))?)?
		if replay.examples.len() != 1 or replay.examples.first()?.input_sha256 != hash!(raw)? {
			return Err(MissingReplayEvidence)
		}
	}
	if name == "spans" {
		cases : List({ file : Str, input : { a : I64, b : I64, c : I64, d : I64 } })
		cases = Json.parse(Path.read_utf8!("tests/fuzz/span_cases.json")?)?
		for case in cases {
			raw = Path.absolute!(Path.utf8("tests/fuzz/corpus/spans/${case.file}"))?
			shown = command!([Path.display(binary), "show", Path.display(raw)], context.work, 10000, 0, Path.join(context.work, "spans-show-${case.file}"))?
			actual = { a: field(shown, "a")?, b: field(shown, "b")?, c: field(shown, "c")?, d: field(shown, "d")? }
			if actual != case.input {
				return Err(ChangedNamedSpan)
			}
		}
	}
	Script.info!("PASS", "${name}: curated replay")
}

field = |shown, name| {
	match shown.split_on("${name}: ") {
		[_, rest] => {
			number = (rest.split_on(",").first() ?? "").split_on("\n").first() ?? ""
			I64.from_str((number.split_on("}").first() ?? "").trim()).map_err(|_| MalformedSpanObservation)
		}
		_ => Err(MalformedSpanObservation)
	}
}

campaign! : Context, Str, Path, FuzzOptions.Options => Try({}, _)
campaign! = |context, name, binary, options| {
	sessions = Path.join(context.work, "campaigns")
	Path.create_all!(sessions)?
	session = Env.create_temp_dir_in!(sessions, name)?
	corpus = Path.join(session, "corpus")
	Path.create_all!(corpus)?
	persistent = Path.join(context.work, "persistent/${name}")
	if Path.exists!(persistent)? {
		for raw in inputs!(persistent)? {
			Path.copy!(raw, Path.join(corpus, Files.name(raw)))?
		}
	}
	for raw in inputs!(Path.utf8("tests/fuzz/corpus/${name}"))? {
		destination = Path.join(corpus, Files.name(raw))
		if Path.exists!(destination)? {
			Path.delete!(destination)?
		}
		Path.copy!(raw, destination)?
	}
	var $source_hashes = []
	for raw in Files.direct_roc_files!(Path.utf8("tests/${name}"))?.concat(Files.direct_roc_files!("package")?) {
		$source_hashes = $source_hashes.append((Path.display(raw), hash!(raw)?))
	}
	var $corpus_hashes = []
	for raw in inputs!(corpus)? {
		$corpus_hashes = $corpus_hashes.append((Files.name(raw), hash!(raw)?))
	}
	metadata = {
		compiler: context.version,
		platform_info: context.dependency,
		host: [context.host.0, context.host.1],
		runner_sha256: hash!("scripts/fuzz.roc")?,
		options_sha256: hash!("scripts/src/FuzzOptions.roc")?,
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
	_ = command!([Path.display(binary), "run", Path.display(corpus), "--report-dir=${Path.display(report_dir)}", "--baseline=${Path.display(baseline)}", "--profile=speed", "--source-revision=${Script.command("git").output!(["rev-parse", "HEAD"])?}", "--roc-version=${context.version}", "--platform-release=${context.dependency.version}", "--platform-sha256=${context.dependency.sha256}", "--runs=${options.runs.to_str()}", "--time=${options.seconds.to_str()}", "--seed=${options.seed.to_str()}", "--max-input-size=256", "--memory-limit=256", "--timeout=2"], session, (options.seconds + 30) * 1000, 0, Path.join(session, "run"))?
	validate_report!(context, report_dir, "matched", Bool.True)?
	_ = inputs!(corpus)?
	if Path.exists!(persistent)? {
		Path.delete_all!(persistent)?
	}
	Path.create_all!(Path.join(context.work, "persistent"))?
	Path.copy_dir!(corpus, persistent)?
	Script.info!("PASS", "${name}: bounded search; evidence ${Path.display(session)}")
}

lifecycle! = |context| {
	bad = build!(context, "lifecycle")?
	fixed = build!(context, "lifecycle_fixed")?
	session = Env.create_temp_dir_in!(context.work, "lifecycle-")?
	corpus = Path.join(session, "corpus")
	Path.create_all!(corpus)?
	Path.write_bytes!(Path.join(corpus, "trigger"), "before*after".to_utf8())?
	failed = command!([Path.display(bad), "run", Path.display(corpus), "--runs=100", "--time=1", "--seed=1", "--max-input-size=32", "--memory-limit=256", "--timeout=2", "--report-dir=${Path.display(Path.join(session, "quality"))}"], session, 15000, 1, Path.join(session, "failure"))?
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
	shown = command!([Path.display(bad), "show", Path.display(raw)], session, 10000, 0, Path.join(session, "show"))?
	if !shown.contains("42") {
		return Err(MissingTrigger)
	}
	_ = command!([Path.display(bad), "replay", Path.display(raw)], session, 10000, 1, Path.join(session, "replay"))?
	match command!([Path.display(bad), "replay", Path.display(raw)], session, 10000, 0, Path.join(session, "gate-control")) {
		Err(UnexpectedExit(Exited(1))) => {}
		_ => return Err(BrokenFailureGate)
	}
	minimized = Path.join(session, "minimized")
	_ = command!([Path.display(bad), "minimize", Path.display(raw), Path.display(minimized)], session, 30000, 0, Path.join(session, "minimize"))?
	if Path.read_bytes!(minimized)? != "*".to_utf8() {
		return Err(UnexpectedMinimization)
	}
	_ = command!([Path.display(bad), "show", Path.display(minimized)], session, 10000, 0, Path.join(session, "show-minimized"))?
	_ = command!([Path.display(bad), "replay", Path.display(minimized)], session, 10000, 1, Path.join(session, "replay-minimized"))?
	_ = command!([Path.display(fixed), "replay", Path.display(minimized)], session, 10000, 0, Path.join(session, "fixed"))?
	regression = Path.absolute!("tests/fuzz/corpus/lifecycle_fixed/byte-42")?
	_ = command!([Path.display(fixed), "replay", Path.display(regression)], session, 10000, 0, Path.join(session, "regression"))?
	Script.info!("PASS", "failure lifecycle: saved/show/replay/minimize, supervisor exit 1 / engine exit 77, fixed regression; ${Path.display(session)}")
}

expect field("{ a: -9223372036854775808, b: 0, c: 1, d: 9223372036854775807 }", "a") == Ok(-9223372036854775808)
expect field("{ a: -1, b: 0, c: 1, d: 9223372036854775807 }", "d") == Ok(9223372036854775807)
expect field("{ a: broken }", "a") == Err(MalformedSpanObservation)

examples! = |context, name, binary, accept| {
	report_dir = Env.create_temp_dir_in!(context.work, "${name}-examples-")?
	baseline = Path.absolute!("tests/fuzz/baselines/${name}.json")?
	_ = command!([Path.display(binary), if (accept) "accept" else "check", "--baseline=${Path.display(baseline)}", "--profile=speed", "--report-dir=${Path.display(report_dir)}"], context.work, 60000, 0, Path.join(report_dir, "supervisor"))?
	validate_report!(context, report_dir, if (accept) "accepted" else "matched", Bool.False)?
	Script.info!("PASS", "${name}: named examples and ${if (accept) "explicitly accepted" else "matched"} allocation baseline; ${Path.display(report_dir)}")
}

validate_report! = |context, directory, baseline, search| {
	report : FuzzEvidence.Report
	report = Json.parse(Path.read_utf8!(Path.join(directory, "report.json"))?)?
	FuzzEvidence.validate(report, context.target, baseline, search)
}

baseline_controls! = |context| {
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
	_ = command!([Path.display(binary), "check", "--baseline=${Path.display(changed)}", "--profile=speed", "--report-dir=${Path.display(changed_report)}"], context.work, 30000, 1, Path.join(work, "changed-supervisor"))?
	result : { outcome : Str, baseline_status : Str, exploration : { status : Str } }
	result = Json.parse(Path.read_utf8!(Path.join(changed_report, "report.json"))?)?
	if result.outcome != "baseline_changed" or result.baseline_status != "changed" or result.exploration.status != "skipped" {
		return Err(BrokenBaselineGate)
	}
	missing_report = Path.join(work, "missing")
	_ = command!([Path.display(binary), "check", "--baseline=${Path.display(Path.join(work, "missing.json"))}", "--profile=speed", "--report-dir=${Path.display(missing_report)}"], context.work, 30000, 0, Path.join(work, "missing-supervisor"))?
	match validate_report!(context, missing_report, "matched", Bool.False) {
		Err(FuzzEvidence) => {}
		_ => return Err(BrokenBaselineGate)
	}
	Script.info!("PASS", "changed baseline fails and skips exploration; unbaselined success is rejected by repository policy")
}
