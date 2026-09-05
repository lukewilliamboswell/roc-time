app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary
import time.PosixSpan

main! = |_args| {
	p = PosixBoundary.from_microseconds(0)
	forged : PosixSpan
	forged = { start: p, end: p }
	_width = PosixSpan.coordinate_width(forged)
	Ok({})
}
