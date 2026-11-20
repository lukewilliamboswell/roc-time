app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

main! = |_args| {
	_invalid = PosixSpan.new({ start: PosixDelta.from_microseconds(0), end: PosixBoundary.from_microseconds(1) })
	Ok({})
}
