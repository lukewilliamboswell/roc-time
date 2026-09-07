app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
}
import RepeatedLocalTime
import time.RfcDateTime

main! = |_| {
	start = "19700101T003000"
	end = "19700101T004500"
	report = RepeatedLocalTime.review(start, end)?
	echo!(report)
	Ok({})
}
