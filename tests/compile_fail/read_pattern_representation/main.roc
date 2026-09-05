app [main!] { time: "../../../package/main.roc" }
import time.CalendarPattern
import time.GregorianDate
main! = |_args| {
	date = GregorianDate.from_fields({ year: 2000, month: 1, day: 1 })?
	pattern = CalendarPattern.new(date, CalendarPattern.defaults(Monthly))?
	_raw = pattern.anchor
	Ok({})
}
