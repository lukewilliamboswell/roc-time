app [main!] { time: "../../../package/main.roc" }
import time.CalendarPattern
import time.DateRecurrence
import time.GregorianDate
main! = |_args| {
	start = GregorianDate.from_fields({ year: 2025, month: 1, day: 1 })?
	end = GregorianDate.from_fields({ year: 2026, month: 1, day: 1 })?
	rule = DateRecurrence.new(start, { pattern: CalendarPattern.defaults(Monthly), termination: Count(3), by_set_pos: [], inclusions: [], exclusions: [] })?
	cursor = DateRecurrence.cursor(rule, { start, end })?
	_raw = cursor.count
	Ok({})
}
