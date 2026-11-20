app [main!] {
	time: "../../../package/main.roc",
}
import time.PosixBoundary

main! = |_args| {
	_invalid = PosixBoundary.order_relative_to(0.I64, PosixBoundary.from_microseconds(1))
	Ok({})
}
