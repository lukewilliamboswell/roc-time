import CalendarPattern
import GregorianDate
import CivilDay

CalendarPatternTests :: [].{}

date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid test date"
}

days = |pattern, index| {
	frame = CalendarPattern.period(pattern, index)?
	var current = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.start))
	end = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.end))
	var result = []
	while current < end {
		value = GregorianDate.from_civil_day(CivilDay.from_day_number(current))?
		if CalendarPattern.matches(pattern, index, value)? {
			result = result.append(GregorianDate.to_fields(value))
		}
		current = current + 1
	}
	Ok(result)
}

# RFC 5545 §3.3.10: invalid generated dates do not become clamped dates.
expect {
	pattern = CalendarPattern.new(date(2025, 1, 31), CalendarPattern.defaults(Monthly))?
	days(pattern, 0)? == [{ year: 2025, month: 1, day: 31 }] and
		days(pattern, 1)? == [] and days(pattern, 2)? == [{ year: 2025, month: 3, day: 31 }]
}

# Whole periods are deliberately independent of DTSTART truncation/BYSETPOS.
expect {
	spec = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	pattern = CalendarPattern.new(date(2025, 1, 20), spec)?
	days(pattern, 0)? == [
		{ year: 2025, month: 1, day: 6 },
		{ year: 2025, month: 1, day: 13 },
		{ year: 2025, month: 1, day: 20 },
		{ year: 2025, month: 1, day: 27 },
	]
}

# Verified RFC erratum 3779 distinguishes ordinal year and ordinal month.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), by_day: [{ ordinal: -1, weekday: Friday }] }
	year = CalendarPattern.new(date(2020, 1, 1), spec)?
	month = CalendarPattern.new(date(2020, 1, 1), { ..spec, by_month: [2] })?
	days(year, 0)? == [{ year: 2020, month: 12, day: 25 }] and
		days(month, 0)? == [{ year: 2020, month: 2, day: 28 }]
}

expect {
	spec = { ..CalendarPattern.defaults(Weekly), interval: 2 }
	monday = CalendarPattern.new(date(1997, 8, 5), spec)?
	sunday = CalendarPattern.new(date(1997, 8, 5), { ..spec, week_start: Sunday })?
	CalendarPattern.period(monday, 1)? == { start: date(1997, 8, 18), end: date(1997, 8, 25) } and
		CalendarPattern.period(sunday, 1)? == { start: date(1997, 8, 17), end: date(1997, 8, 24) }
}

expect {
	spec = { ..CalendarPattern.defaults(Yearly), by_week_no: [1], by_day: [{ ordinal: 0, weekday: Monday }] }
	pattern = CalendarPattern.new(date(1997, 1, 1), spec)?
	days(pattern, 0)? == [{ year: 1997, month: 12, day: 29 }]
}

# Independent seven-day calendar rows expose dateutil's adjacent-year gaps.
# Friday-start week-year 2001 has 53 weeks; its first begins 2000-12-29.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), week_start: Friday, by_week_no: [-53] }
	pattern = CalendarPattern.new(date(2000, 1, 1), spec)?
	days(pattern, 0)? == [
		{ year: 2000, month: 12, day: 29 },
		{ year: 2000, month: 12, day: 30 },
		{ year: 2000, month: 12, day: 31 },
	]
}

# With Saturday-start weeks, January 1–2 2015 belong to week 52, not 53.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), week_start: Saturday, by_week_no: [53] }
	pattern = CalendarPattern.new(date(2015, 1, 1), spec)?
	days(pattern, 0)? == []
}

expect {
	month = CalendarPattern.new(date(0, 1, 31), { ..CalendarPattern.defaults(Monthly), by_month_day: [-1, -1] })?
	year = CalendarPattern.new(date(0, 1, 1), { ..CalendarPattern.defaults(Yearly), by_year_day: [-1, 60] })?
	days(month, 1)? == [{ year: 0, month: 2, day: 29 }] and
		days(year, 0)? == [{ year: 0, month: 2, day: 29 }, { year: 0, month: 12, day: 31 }]
}

expect {
	anchor = date(2000, 1, 1)
	base = CalendarPattern.defaults(Monthly)
	status(anchor, { ..base, interval: 0 }) == Err(InvalidInterval) and
		status(anchor, { ..base, by_month_day: [0] }) == Err(InvalidSelector("BYMONTHDAY")) and
			status(anchor, { ..base, by_week_no: [1] }) == Err(InvalidCombination("BYWEEKNO requires YEARLY")) and
				status(anchor, { ..base, frequency: Weekly, by_day: [{ ordinal: 1, weekday: Monday }] }) == Err(InvalidCombination("ordinal BYDAY"))
}

expect {
	base = CalendarPattern.defaults(Yearly)
	anchor = date(2000, 1, 1)
	status(anchor, { ..base, interval: I64.highest }) == Err(InvalidInterval) and
		status(anchor, { ..base, by_month: [13] }) == Err(InvalidSelector("BYMONTH")) and
			status(anchor, { ..base, by_year_day: [367] }) == Err(InvalidSelector("BYYEARDAY")) and
				status(anchor, { ..base, by_week_no: [0] }) == Err(InvalidSelector("BYWEEKNO")) and
					status(anchor, { ..base, by_day: [{ ordinal: 54, weekday: Monday }] }) == Err(InvalidSelector("BYDAY")) and
						status(anchor, { ..base, by_month: List.repeat(1, 4097) }) == Err(TooManySelectors)
}

expect {
	pattern = CalendarPattern.new(date(-2147483648, 1, 1), CalendarPattern.defaults(Monthly))?
	last = CalendarPattern.new(date(2147483647, 12, 1), CalendarPattern.defaults(Monthly))?
	CalendarPattern.period(pattern, U64.highest) == Err(OutOfRange) and
		CalendarPattern.period(last, 0) == Err(OutOfRange)
}

status = |anchor, spec| match CalendarPattern.new(anchor, spec) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
