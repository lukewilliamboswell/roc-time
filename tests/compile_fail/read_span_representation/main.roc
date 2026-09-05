app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary
import time.PosixSpan

main! = |_args| {
	span = PosixSpan.microsecond_at(PosixBoundary.from_microseconds(0))?
	_raw = span.start
	Ok({})
}
