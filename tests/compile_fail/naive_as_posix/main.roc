app [main!] {
	time: "../../../package/main.roc",
}

import time.Nanosecond.LocalDateTime as NanoLocalDateTime
import time.Nanosecond.PosixBoundary as PosixNanoBoundary

main! = |_args| {
	_ = PosixNanoBoundary.to_nanoseconds(NanoLocalDateTime.from_gregorian_local_nanoseconds(-1))
	Ok({})
}
