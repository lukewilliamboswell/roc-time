#!/usr/bin/env roc-stable
app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import cli.Env
import cli.OsStr
import cli.Path
import src/OracleCases
import src/OracleManifest
import src/OracleReplay
import src/OracleStages
import src/Script

main! = |_args| {
	for name in ["gregorian", "julian", "zones", "calendar_pattern", "rfc_date", "rfc_timed"] {
		manifest = OracleManifest.parse(Path.read_utf8!(Path.utf8("tests/oracles/${name}-manifest.toml"))?, name)?
		corpus = Path.utf8("tests/oracles/${name}.jsonl")
		actual = Script.command("sha256sum").output!([Path.to_os_str(corpus)])?
		if !actual.starts_with("${manifest.corpus_sha256} ") {
			return Err(CorpusIntegrity(name))
		}
		cases = OracleCases.load(Path.read_utf8!(corpus)?, manifest.case_count, name)?
		Script.info!("RECORDS", "${name}: ${cases.len().to_str()}")?
	}
	compiler = Script.roc_nightly!()?
	work = Env.create_temp_dir_in!(Path.absolute!(".roc-time-tmp")?, "oracle-transport-")?
	binary = Path.join(work, "native")
	compiler.cmd(["check", "tests/oracle_transport/main.roc"]).exec_cmd!()?
	compiler.cmd(["build", "tests/oracle_transport/main.roc", "--debug", OsStr.from_str("--output=${Path.display(binary)}")]).timeout_ms(180000).exec_cmd!()?
	match OracleStages.run!([Path.display(binary), "0", "invalid_operation", "0"], work, "stage-exit-control") {
		Err(StageStatus(_, Exited(7))) => {}
		other => return Script.fail!("command exit control ${Str.inspect(other)}")
	}
	for (operation, expected) in [("timeout", Timeout), ("overflow", OutputLimit), ("invalid_operation", Status), ("invalid_utf8", InvalidUtf8), ("wrong", Mismatch), ("bad_metrics", InvalidMetrics)] {
		case = { id: "0", operation, input: ["0"], expected: ["ok", "0"], evidence: "supervision-control" }
		session = Path.join(work, operation)
		Path.create_all!(session)?
		match OracleReplay.one!(binary, case, session, 200) {
			Err(OracleCaseFailure(failure)) if failure.id == "0" and failure.kind == expected => {}
			other => return Script.fail!("${operation}: incorrect failure control ${Str.inspect(other)}")
		}
		file = Path.join(session, "failure-0.json")
		if !Path.read_utf8!(file)?.contains(operation) {
			return Err(MissingFailureInput)
		}
		size = U64.from_str(Script.command("wc").output!(["-c", Path.to_os_str(file)])?.trim().split_on(" ").first()?)?
		if size > 20000 {
			return Err(UnboundedFailureArtifact)
		}
		Script.info!("CONTROL", operation)?
	}
	cases = [0.U64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(|id| { id: id.to_str(), operation: "control", input: [if (U64.rem_by(id, 2) == 0) "150" else "10"], expected: ["ok", "0"], evidence: "supervision-control" })
	Path.write_utf8!(Path.join(work, "ledger"), "0,0")?
	results = OracleReplay.replay!(binary, cases, work, 3)?
	if results.map(|result| result.id) != cases.map(|case| case.id) or Path.read_utf8!(Path.join(work, "ledger"))? != "0,3" {
		return Err(IncorrectConcurrency)
	}
	serial = Path.join(work, "serial-control")
	Path.create_all!(serial)?
	Path.write_utf8!(Path.join(serial, "ledger"), "0,0")?
	match OracleReplay.replay!(binary, cases, serial, 1) {
		Err(OracleCaseFailure(failure)) if failure.id == "0" and failure.kind == Status => {}
		_ => return Err(BrokenParallelismControl)
	}
	if !Path.read_utf8!(Path.join(serial, "failure-0.json"))?.contains("PeerBarrier") {
		return Err(WrongParallelismFailure)
	}
	Script.info!("PASS", "ordered replay with 3 overlapping workers; bounded output, deadlines, malformed output and retained failures: ${Path.display(work)}")
}
