app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import cli.Path
import cli.OsStr
import cli.Sleep
import cli.Stderr
import cli.Stdout

# Deliberately artificial transport fixture. An atomic directory lock protects
# an independent live-process ledger; zero metrics are protocol controls, not
# allocation measurements or evidence about temporal behavior.
main! = |args| {
	(id, operation, delay) = match args.map(OsStr.display) {
		[identity, action, millis] => (identity, action, U64.from_str(millis)?)
		_ => return Err(Arguments)
	}
	if operation == "timeout" {
		Sleep.millis!(30000)?
	}
	if operation == "overflow" {
		return Stdout.write_bytes!("x".repeat(65536).to_utf8())
	}
	if operation == "invalid_utf8" {
		return Stdout.write_bytes!([255])
	}
	if operation == "invalid_operation" {
		return Err(Exit(7))
	}
	if operation == "control" {
		record!(1)?
		if ["0", "1", "2"].contains(id) {
			Path.write_utf8!(Path.utf8("started-${id}"), "started")?
			barrier!()?
		}
	}
	Sleep.millis!(delay)?
	if operation == "control" {
		record!(-1)?
	}
	if operation == "bad_metrics" {
		Stderr.line!("unexpected warning")?
	}
	Stderr.line!("ROC_METRICS protocol=1 allocations=0 requested_bytes=0 deallocations=0 work=1")?
	Stdout.line!("${id}\tok\t${if (operation == "wrong") "1" else "0"}")
}

# The bounded barrier makes serial execution fail instead of relying on a
# wall-clock duration threshold or comparing process-local clock readings.
barrier! = || {
	for _ in (0.U64).until(2000) {
		if Path.exists!("started-0")? and Path.exists!("started-1")? and Path.exists!("started-2")? {
			return Ok({})
		}
		Sleep.millis!(1)?
	}
	Err(PeerBarrier)
}

lock! = || {
	for _ in (0.U64).until(2000) {
		match Path.create_dir!("ledger-lock") {
			Ok(_) => return Ok({})
			Err(PathErr(AlreadyExists, _)) => Sleep.millis!(1).map_err(|error| LedgerSleep(error))?
			Err(error) => return Err(LedgerIO(error))
		}
	}
	Err(LockBudget)
}

record! = |delta| {
	lock!()?
	(active, peak) = match Path.read_utf8!("ledger")?.split_on(",") {
		[a, p] => (I64.from_str(a)?, I64.from_str(p)?)
		_ => return Err(LedgerSyntax)
	}
	next = active + delta
	if next < 0 {
		return Err(LedgerUnderflow)
	}
	maximum = if (next > peak) next else peak
	Path.write_utf8!("ledger", "${next.to_str()},${maximum.to_str()}")?
	Path.delete_empty!("ledger-lock")
}
