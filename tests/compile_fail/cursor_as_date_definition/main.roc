app [main!] { time: "../../../package/main.roc" }
import time.GregorianDate
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Date as DateRecurrence
import time.ICalendar.DateRule as ICalDateRule

main! = |_args| {
	start = GregorianDate.from_fields({ year: 2025, month: 1, day: 1 })?
	end = GregorianDate.from_fields({ year: 2026, month: 1, day: 1 })?
	rule = DateRecurrence.new(start, { pattern: CalendarPattern.defaults(Daily), termination: Forever, by_set_pos: [], inclusions: [], exclusions: [] })?
	cursor = DateRecurrence.cursor(rule, { start, end })?
	_ = ICalDateRule.to_parts(cursor)
	Ok({})
}
