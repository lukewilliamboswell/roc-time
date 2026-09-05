app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

main! = |_args| {
	_invalid = PosixSpan.new(PosixDelta.from_microseconds(0), PosixBoundary.from_microseconds(1))
	Ok({})
}
