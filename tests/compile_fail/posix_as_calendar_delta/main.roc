app [main!] {
	time: "../../../package/main.roc",
}
import time.CalendarArithmetic
import time.GregorianDate
import time.PosixDelta

main! = |_args| {
	date = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
	_invalid = CalendarArithmetic.shift_day(date, PosixDelta.from_microseconds(1), Clamp)
	Ok({})
}
