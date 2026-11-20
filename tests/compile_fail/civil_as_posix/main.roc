app [main!] {
	time: "../../../package/main.roc",
}
import time.Calendar.CivilDay as CivilDay
import time.PosixBoundary
import time.PosixSpan

main! = |_args| {
	_invalid = PosixSpan.new({ start: CivilDay.from_day_number(0), end: PosixBoundary.from_microseconds(1) })
	Ok({})
}
