app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	time: "../../package/main.roc",
}
import pf.Utc
import pf.OsStr
import pf.Stdout
import Deadline

# Check a deadline against the host clock, or against the UTC instant given as
# the one argument, which makes the record reproducible:
#
#     roc main.roc
#     roc main.roc 2026-10-12T01:02:03Z
main! = |args| {
	now = match args.map(OsStr.display) {
		[instant] => Deadline.at(instant)?
		_ => Deadline.acquire_nanoseconds(Utc.now!().to_nanos_since_epoch())?
	}
	record = Deadline.evaluate(now, "2030-01-01T00:00:00Z")?
	Stdout.line!(Deadline.encode(record))?
	Ok({})
}
