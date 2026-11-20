app [main!] {
	time: "../../../package/main.roc",
}

import time.NanoLocalDateTime
import time.PosixNanoBoundary

main! = |_args| {
	_ = PosixNanoBoundary.to_nanoseconds(NanoLocalDateTime.from_gregorian_local_nanoseconds(-1))
	Ok({})
}
