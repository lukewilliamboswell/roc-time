app [main!] {
	time: "../../package/main.roc",
}

import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.Coverage
import time.EventCollection
import time.CalendarPattern
import time.GregorianDate
import time.DateRecurrence

# Positive control for compile-failure checks: the same imports and valid
# domain combinations must succeed independently of application examples.
main! = |_args| {
	start = PosixBoundary.from_microseconds(0)
	end = PosixBoundary.shift(start, PosixDelta.from_microseconds(1))?
	span = PosixSpan.new(start, end)?
	_events = EventCollection.from_entries([{ id: 0.U64, span }])?
	_width = Coverage.coordinate_width(Coverage.from_spans([span]))?
	date = GregorianDate.from_fields({ year: 2000, month: 1, day: 1 })?
	pattern = CalendarPattern.new(date, CalendarPattern.defaults(Monthly))?
	_matches = CalendarPattern.matches(pattern, 0, date)?
	rule = DateRecurrence.new(date, { pattern: CalendarPattern.defaults(Monthly), termination: Count(3), by_set_pos: [], inclusions: [], exclusions: [] })?
	window_end = GregorianDate.from_fields({ year: 2001, month: 1, day: 1 })?
	cursor = DateRecurrence.cursor(rule, { start: date, end: window_end })?
	_batch = DateRecurrence.Cursor.collect(cursor, { max_steps: 1000, max_buffered: 366, max_occurrences: 10 })?
	Ok({})
}
