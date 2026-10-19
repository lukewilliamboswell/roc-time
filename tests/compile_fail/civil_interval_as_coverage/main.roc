app [main!] { time: "../../../package/main.roc" }
import time.CalendarInterval
import time.Coverage
import time.PosixBoundary
main! = |_args| {
	description = CalendarInterval.new(Unknown, Open)?
	_invalid = Coverage.contains(description, PosixBoundary.from_microseconds(0))
	Ok({})
}
