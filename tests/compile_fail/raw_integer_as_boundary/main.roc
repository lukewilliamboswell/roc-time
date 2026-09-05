app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary

main! = |_args| {
	_invalid = PosixBoundary.compare(0.I64, PosixBoundary.from_microseconds(1))
	Ok({})
}
