app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	time: "../../package/main.roc",
}
import pf.Utc
import pf.Stdout
import Deadline

main! = |_args| {
	now = Deadline.acquire_nanoseconds(Utc.now!().to_nanos_since_epoch())?
	record = Deadline.evaluate(now, "2030-01-01T00:00:00Z")?
	Stdout.line!(Deadline.encode(record))?
	Ok({})
}
