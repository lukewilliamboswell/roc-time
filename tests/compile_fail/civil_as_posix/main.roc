app [main!] {
	time: "../../../package/main.roc",
}
import time.CivilDay
import time.PosixBoundary
import time.PosixSpan

main! = |_args| {
	_invalid = PosixSpan.new(CivilDay.from_day_number(0), PosixBoundary.from_microseconds(1))
	Ok({})
}
