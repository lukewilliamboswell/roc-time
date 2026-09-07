app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
}
import pf.Utc
import pf.Stdout
import Deadline

main! = |_args| {
	now = Deadline.acquire_positive_nanoseconds(Utc.now!())?
	record = Deadline.evaluate(now, "2030-01-01T00:00:00Z")?
	Stdout.line!(Deadline.encode(record))?
	Ok({})
}
