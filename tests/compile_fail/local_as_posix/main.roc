app [main!] {
	time: "../../../package/main.roc",
}
import time.CalendarDate
import time.ClockTime
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan

main! = |_args| {
	date = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	_invalid = PosixSpan.new(LocalDateTime.new(date, clock), PosixBoundary.from_microseconds(1))
	Ok({})
}
