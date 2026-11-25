import fuzz.Solve
import time.GregorianDate
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Date as DateRecurrence
import time.Recurrence.DateCursor as DateCursor

PeriodOrder := [].{}

date = |year, month, day| GregorianDate.from_fields({ year, month, day }) ?? crash "fixture date"

# R05/R11. With an interval of two, a product in a 64-bit carrier can
# map a positive index to step zero. Ask for that alias and exercise both
# public period operations. The mathematical start is far past the provider.
expect {
	result = Solve.find_within(
		Solve.u64_in(1, U64.highest),
		|index| index.plus_wrap(index).eq(Solve.Uint.from_u64(0)),
		1000,
	)?
	match result {
		Found(witness) => {
			index = witness.value()
			anchor = date(2000, 1, 1)
			pattern = CalendarPattern.new(anchor, { ..CalendarPattern.defaults(Weekly), interval: 2 })?
			index == 9223372036854775808 and
				CalendarPattern.start_relative_to(pattern, { period_index: index, boundary: anchor }) == After and
					CalendarPattern.period(pattern, index) == Err(OutOfRange)
		}
		_ => False
	}
}

# The minimum year has the same weekday grid as 1952. Its January 1 is
# Tuesday, so a Monday-start period begins one day before the provider.
# The next period can still be constructed and starts on January 7.
expect {
	minimum = -2147483648.I64
	anchor = date(minimum, 1, 1)
	week = CalendarPattern.new(anchor, CalendarPattern.defaults(Weekly))?
	second_start = date(minimum, 1, 7)
	CalendarPattern.period(week, 0) == Err(OutOfRange) and
		CalendarPattern.start_relative_to(week, { period_index: 0, boundary: anchor }) == Before and
			CalendarPattern.start_relative_to(week, { period_index: 1, boundary: second_start }) == Same and
				CalendarPattern.period(week, 1) == Ok({ start: second_start, end: date(minimum, 1, 14) })
}

# A finite query can prove completion before building the next full period.
# Only the anchor can land in the window with a cadence of I32.highest weeks.
expect {
	anchor = date(2147483646, 12, 31)
	spec = { ..CalendarPattern.defaults(Weekly), interval: 2147483647 }
	rule = DateRecurrence.new(anchor, { pattern: spec, termination: Forever, by_set_pos: [], inclusions: [], exclusions: [] })?
	cursor = DateRecurrence.cursor(rule, { start: anchor, end: date(2147483647, 12, 31) })?
	batch = DateCursor.collect(cursor, { max_steps: 64, max_buffered: 7, max_occurrences: 2 })?
	batch.dates == [anchor] and match batch.status {
		Complete => True
		Limited(_) => False
	}
}

# RFC 5545 §3.3.10 names week 1 by the first week with at least four
# in-year days. The minimum year shares 1952's weekday grid, so with
# Wednesday starts January 1 is the final day of the prior week-year.
# https://www.rfc-editor.org/rfc/rfc5545#section-3.3.10
expect {
	minimum = -2147483648.I64
	anchor = date(minimum, 1, 1)
	next_day = date(minimum, 1, 2)
	spec = { ..CalendarPattern.defaults(Yearly), week_start: Wednesday, by_week_no: [-1] }
	pattern = CalendarPattern.new(anchor, spec)?
	rule = DateRecurrence.new(anchor, { pattern: spec, termination: Count(1), by_set_pos: [], inclusions: [], exclusions: [] })?
	cursor = DateRecurrence.cursor(rule, { start: anchor, end: next_day })?
	batch = DateCursor.collect(cursor, { max_steps: 512, max_buffered: 366, max_occurrences: 2 })?
	CalendarPattern.matches(pattern, { period_index: 0, date: anchor }) == Ok(True) and
		CalendarPattern.matches(pattern, { period_index: 0, date: next_day }) == Ok(False) and
			batch.dates == [anchor] and match batch.status {
				Complete => True
				Limited(_) => False
			}
}

# The penultimate year shares 2046's weekday grid. December 31 is the
# Monday beginning week 1 of the following year. Its week count needs a
# mathematical boundary after the provider, although the civil period fits.
expect {
	year = 2147483646.I64
	spec = { ..CalendarPattern.defaults(Yearly), by_week_no: [1] }
	pattern = CalendarPattern.new(date(year, 1, 1), spec)?
	CalendarPattern.matches(pattern, { period_index: 0, date: date(year, 12, 31) }) == Ok(True) and
		CalendarPattern.matches(pattern, { period_index: 0, date: date(year, 12, 30) }) == Ok(False)
}
