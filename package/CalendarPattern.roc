import CivilDay
import GregorianDate

## Validated Gregorian date selectors within anchored calendar periods.
## This is the candidate layer: it does not apply DTSTART truncation, COUNT,
## UNTIL, BYSETPOS, clock selectors, exclusions or zone interpretation.
## Week ordinals use the date's week-numbering year, which can differ from its
## civil year. Negative positions count back from that numbering year's end.
CalendarPattern :: { anchor : GregorianDate, spec : Spec }.{
	Frequency : [Daily, Weekly, Monthly, Yearly]
	Weekday : [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
	Spec : {
		frequency : Frequency,
		interval : I64,
		week_start : Weekday,
		by_month : List(U8),
		by_month_day : List(I8),
		by_year_day : List(I16),
		by_week_no : List(I8),
		by_day : List({ ordinal : I8, weekday : Weekday }),
	}

	## Read validated selector declarations without evaluating a period.
	definition : CalendarPattern -> Spec
	definition = |pattern| pattern.spec
	defaults : Frequency -> Spec
	defaults = |frequency| { frequency, interval: 1, week_start: Monday, by_month: [], by_month_day: [], by_year_day: [], by_week_no: [], by_day: [] }

	## RFC date-selector domains and combinations; at most 4096 supplied values
	## per selector. Duplicates have set meaning and do not duplicate candidates.
	new : GregorianDate, Spec -> Try(CalendarPattern, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), ..])
	new = |anchor, spec| {
		validate(spec)?
		Ok({ anchor, spec })
	}

	## A whole frequency period, including days before the anchor in period zero.
	## Exclusive end must fit the Gregorian provider. No clamping or clipping.
	## Fixed work independent of index; intermediate arithmetic uses I128.
	period : CalendarPattern, U64 -> Try({ start : GregorianDate, end : GregorianDate }, [OutOfRange, ..])
	period = |pattern, index| {
		fields = GregorianDate.to_fields(pattern.anchor)
		step = index.to_i128() * pattern.spec.interval.to_i128()
		match pattern.spec.frequency {
			Daily => {
				start = number(pattern.anchor).to_i128() + step
				Ok({ start: from_number(start)?, end: from_number(start + 1)? })
			}
			Weekly => {
				day = number(pattern.anchor)
				back = I64.mod_by(weekday_number(day) - weekday_index(pattern.spec.week_start), 7)
				start = (day - back).to_i128() + step * 7
				Ok({ start: from_number(start)?, end: from_number(start + 7)? })
			}
			Monthly => {
				month = fields.year.to_i128() * 12 + fields.month.to_i128() - 1 + step
				Ok({ start: month_start(month)?, end: month_start(month + 1)? })
			}
			Yearly => {
				year = fields.year.to_i128() + step
				Ok({ start: january(year)?, end: january(year + 1)? })
			}
		}
	}

	## Test one date against one period. Cost is O(s) supplied selector values,
	## with bounded calendar arithmetic; no series scan or candidate lists.
	## BYSETPOS must operate on completed full candidates, after this layer.
	## Weekly defaults retain the anchor weekday; monthly defaults retain its
	## month-day when neither BYDAY nor BYMONTHDAY expands the period. Yearly
	## defaults retain month/day only in the absence of expanding date selectors
	## (an explicit BYMONTH can select multiple copies of the anchor month-day).
	## Standards adapters supply any additional format-specific defaults first.
	matches : CalendarPattern, U64, GregorianDate -> Try(Bool, [OutOfRange, ..])
	matches = |pattern, index, date| {
		frame = period(pattern, index)?
		if date < frame.start or date >= frame.end {
			return Ok(False)
		}
		if !matches_filters(pattern.spec, date)? {
			return Ok(False)
		}
		spec = pattern.spec
		fields = GregorianDate.to_fields(date)
		anchor = GregorianDate.to_fields(pattern.anchor)
		weekday = weekday_number(number(date))
		# Defaults supply missing expansion fields, not extra filters when other
		# date selectors already expanded the period.
		if spec.frequency == Weekly and spec.by_day.is_empty() {
			return Ok(weekday == weekday_number(number(pattern.anchor)))
		}
		if spec.frequency == Monthly and spec.by_day.is_empty() and spec.by_month_day.is_empty() {
			return Ok(fields.day == anchor.day)
		}
		if spec.frequency == Yearly and spec.by_day.is_empty() and spec.by_month_day.is_empty() and spec.by_year_day.is_empty() and spec.by_week_no.is_empty() {
			return Ok(fields.day == anchor.day and (!spec.by_month.is_empty() or fields.month == anchor.month))
		}
		Ok(True)
	}

	## Date restrictions without a frequency's expansion defaults. Subdaily
	## periods use these same selector predicates after choosing their date.
	Filter :: { spec : CalendarPattern.Spec }.{
		Spec : { by_month : List(U8), by_month_day : List(I8), by_year_day : List(I16), by_day : List(Weekday) }
		new : Spec -> Try(Filter, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), ..])
		new = |filters| {
			if filters.by_month.len() > 4096 or filters.by_month_day.len() > 4096 or filters.by_year_day.len() > 4096 or filters.by_day.len() > 4096 {
				return Err(TooManySelectors)
			}
			spec = { ..CalendarPattern.defaults(Yearly), by_month: filters.by_month, by_month_day: filters.by_month_day, by_year_day: filters.by_year_day, by_day: filters.by_day.map(|weekday| { ordinal: 0.I8, weekday }) }
			validate(spec)?
			Ok({ spec: spec })
		}

		## Shared predicate storage only: frequency/interval/week_start are
		## placeholders, not a recurrence frequency or expansion defaults.
		definition : Filter -> CalendarPattern.Spec
		definition = |filter| filter.spec
		matches : Filter, GregorianDate -> Try(Bool, [OutOfRange, ..])
		matches = |filter, date| matches_filters(filter.spec, date)
	}

	to_inspect : CalendarPattern -> Str
	to_inspect = |pattern| "CalendarPattern(${Str.inspect(pattern.spec.frequency)}, interval=${pattern.spec.interval.to_str()}, anchor=${Str.inspect(pattern.anchor)})"
}

number = |date| CivilDay.to_day_number(GregorianDate.to_civil_day(date))

from_number = |value| {
	narrowed = match I128.to_i64_try(value) {
		Ok(n) => n
		Err(_) => return Err(OutOfRange)
	}
	GregorianDate.from_civil_day(CivilDay.from_day_number(narrowed))
}

january = |year| {
	if year < -2147483648 or year > 2147483647 {
		return Err(OutOfRange)
	}
	narrowed = match I128.to_i64_try(year) {
		Ok(n) => n
		Err(_) => crash "Validated Gregorian year"
	}
	match GregorianDate.from_fields({ year: narrowed, month: 1, day: 1 }) {
		Ok(value) => Ok(value)
		Err(_) => crash "Validated Gregorian January"
	}
}

month_start = |month| {
	year = I128.div_floor_by(month, 12)
	first = january(year)?
	month_number = match I128.to_u8_try(I128.mod_by(month, 12) + 1) {
		Ok(value) => value
		Err(_) => crash "Gregorian month remainder"
	}
	match GregorianDate.from_fields({ year: GregorianDate.to_fields(first).year, month: month_number, day: 1 }) {
		Ok(value) => Ok(value)
		Err(_) => crash "Validated Gregorian month"
	}
}

weekday_number = |day| I64.mod_by(day + 3, 7)

weekday_index : CalendarPattern.Weekday -> I64
weekday_index = |weekday| match weekday {
	Monday => 0
	Tuesday => 1
	Wednesday => 2
	Thursday => 3
	Friday => 4
	Saturday => 5
	Sunday => 6
}

ordinal_matches = |selected, position, total| selected == position or selected == position - total - 1

week_start = |year, weekday| {
	jan_four = number(january(year)?) + 3
	Ok(jan_four - I64.mod_by(weekday_number(jan_four) - weekday_index(weekday), 7))
}

week_position = |date, weekday| {
	day = number(date)
	var $year = GregorianDate.to_fields(date).year.to_i128()
	var $start = week_start($year, weekday)?
	var $end = week_start($year + 1, weekday)?
	if day < $start {
		$year = $year - 1
		$end = $start
		$start = week_start($year, weekday)?
	} else if day >= $end {
		$year = $year + 1
		$start = $end
		$end = week_start($year + 1, weekday)?
	}
	Ok({ position: I64.div_trunc_by(day - $start, 7) + 1, total: I64.div_trunc_by($end - $start, 7) })
}

test_calendarpattern_date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid test test_calendarpattern_date"
}

test_calendarpattern_days = |pattern, index| {
	frame = CalendarPattern.period(pattern, index)?
	var $current = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.start))
	end = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.end))
	var $result = []
	while $current < end {
		value = GregorianDate.from_civil_day(CivilDay.from_day_number($current))?
		if CalendarPattern.matches(pattern, index, value)? {
			$result = $result.append(GregorianDate.to_fields(value))
		}
		$current = $current + 1
	}
	Ok($result)
}

# RFC 5545 §3.3.10: invalid generated dates do not become clamped dates.
expect {
	pattern = CalendarPattern.new(test_calendarpattern_date(2025, 1, 31), CalendarPattern.defaults(Monthly))?
	test_calendarpattern_days(pattern, 0)? == [{ year: 2025, month: 1, day: 31 }] and
		test_calendarpattern_days(pattern, 1)? == [] and test_calendarpattern_days(pattern, 2)? == [{ year: 2025, month: 3, day: 31 }]
}

# Whole periods are deliberately independent of DTSTART truncation/BYSETPOS.
expect {
	spec = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	pattern = CalendarPattern.new(test_calendarpattern_date(2025, 1, 20), spec)?
	test_calendarpattern_days(pattern, 0)? == [
		{ year: 2025, month: 1, day: 6 },
		{ year: 2025, month: 1, day: 13 },
		{ year: 2025, month: 1, day: 20 },
		{ year: 2025, month: 1, day: 27 },
	]
}

# Verified RFC erratum 3779 distinguishes ordinal year and ordinal month.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), by_day: [{ ordinal: -1, weekday: Friday }] }
	year = CalendarPattern.new(test_calendarpattern_date(2020, 1, 1), spec)?
	month = CalendarPattern.new(test_calendarpattern_date(2020, 1, 1), { ..spec, by_month: [2] })?
	test_calendarpattern_days(year, 0)? == [{ year: 2020, month: 12, day: 25 }] and
		test_calendarpattern_days(month, 0)? == [{ year: 2020, month: 2, day: 28 }]
}

expect {
	spec = { ..CalendarPattern.defaults(Weekly), interval: 2 }
	monday = CalendarPattern.new(test_calendarpattern_date(1997, 8, 5), spec)?
	sunday = CalendarPattern.new(test_calendarpattern_date(1997, 8, 5), { ..spec, week_start: Sunday })?
	CalendarPattern.period(monday, 1)? == { start: test_calendarpattern_date(1997, 8, 18), end: test_calendarpattern_date(1997, 8, 25) } and
		CalendarPattern.period(sunday, 1)? == { start: test_calendarpattern_date(1997, 8, 17), end: test_calendarpattern_date(1997, 8, 24) }
}

expect {
	spec = { ..CalendarPattern.defaults(Yearly), by_week_no: [1], by_day: [{ ordinal: 0, weekday: Monday }] }
	pattern = CalendarPattern.new(test_calendarpattern_date(1997, 1, 1), spec)?
	test_calendarpattern_days(pattern, 0)? == [{ year: 1997, month: 12, day: 29 }]
}

# Independent seven-day calendar rows expose dateutil's adjacent-year gaps.
# Friday-start week-year 2001 has 53 weeks; its first begins 2000-12-29.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), week_start: Friday, by_week_no: [-53] }
	pattern = CalendarPattern.new(test_calendarpattern_date(2000, 1, 1), spec)?
	test_calendarpattern_days(pattern, 0)? == [
		{ year: 2000, month: 12, day: 29 },
		{ year: 2000, month: 12, day: 30 },
		{ year: 2000, month: 12, day: 31 },
	]
}

# With Saturday-start weeks, January 1–2 2015 belong to week 52, not 53.
expect {
	spec = { ..CalendarPattern.defaults(Yearly), week_start: Saturday, by_week_no: [53] }
	pattern = CalendarPattern.new(test_calendarpattern_date(2015, 1, 1), spec)?
	test_calendarpattern_days(pattern, 0)? == []
}

expect {
	month = CalendarPattern.new(test_calendarpattern_date(0, 1, 31), { ..CalendarPattern.defaults(Monthly), by_month_day: [-1, -1] })?
	year = CalendarPattern.new(test_calendarpattern_date(0, 1, 1), { ..CalendarPattern.defaults(Yearly), by_year_day: [-1, 60] })?
	test_calendarpattern_days(month, 1)? == [{ year: 0, month: 2, day: 29 }] and
		test_calendarpattern_days(year, 0)? == [{ year: 0, month: 2, day: 29 }, { year: 0, month: 12, day: 31 }]
}

expect {
	anchor = test_calendarpattern_date(2000, 1, 1)
	base = CalendarPattern.defaults(Monthly)
	test_calendarpattern_status(anchor, { ..base, interval: 0 }) == Err(InvalidInterval) and
		test_calendarpattern_status(anchor, { ..base, by_month_day: [0] }) == Err(InvalidSelector("BYMONTHDAY")) and
			test_calendarpattern_status(anchor, { ..base, by_week_no: [1] }) == Err(InvalidCombination("BYWEEKNO requires YEARLY")) and
				test_calendarpattern_status(anchor, { ..base, frequency: Weekly, by_day: [{ ordinal: 1, weekday: Monday }] }) == Err(InvalidCombination("ordinal BYDAY"))
}

expect {
	base = CalendarPattern.defaults(Yearly)
	anchor = test_calendarpattern_date(2000, 1, 1)
	test_calendarpattern_status(anchor, { ..base, interval: I64.highest }) == Err(InvalidInterval) and
		test_calendarpattern_status(anchor, { ..base, by_month: [13] }) == Err(InvalidSelector("BYMONTH")) and
			test_calendarpattern_status(anchor, { ..base, by_year_day: [367] }) == Err(InvalidSelector("BYYEARDAY")) and
				test_calendarpattern_status(anchor, { ..base, by_week_no: [0] }) == Err(InvalidSelector("BYWEEKNO")) and
					test_calendarpattern_status(anchor, { ..base, by_day: [{ ordinal: 54, weekday: Monday }] }) == Err(InvalidSelector("BYDAY")) and
						test_calendarpattern_status(anchor, { ..base, by_month: List.repeat(1, 4097) }) == Err(TooManySelectors)
}

expect {
	pattern = CalendarPattern.new(test_calendarpattern_date(-2147483648, 1, 1), CalendarPattern.defaults(Monthly))?
	last = CalendarPattern.new(test_calendarpattern_date(2147483647, 12, 1), CalendarPattern.defaults(Monthly))?
	CalendarPattern.period(pattern, U64.highest) == Err(OutOfRange) and
		CalendarPattern.period(last, 0) == Err(OutOfRange)
}

test_calendarpattern_status = |anchor, spec| match CalendarPattern.new(anchor, spec) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

validate = |spec| {
	if spec.interval < 1 or spec.interval > 2147483647 {
		return Err(InvalidInterval)
	}
	if spec.by_month.len() > 4096 or spec.by_month_day.len() > 4096 or spec.by_year_day.len() > 4096 or spec.by_week_no.len() > 4096 or spec.by_day.len() > 4096 {
		return Err(TooManySelectors)
	}
	for month in spec.by_month {
		if month < 1 or month > 12 {
			return Err(InvalidSelector("BYMONTH"))
		}
	}
	for day in spec.by_month_day {
		if day == 0 or day < -31 or day > 31 {
			return Err(InvalidSelector("BYMONTHDAY"))
		}
	}
	for day in spec.by_year_day {
		if day == 0 or day < -366 or day > 366 {
			return Err(InvalidSelector("BYYEARDAY"))
		}
	}
	for week in spec.by_week_no {
		if week == 0 or week < -53 or week > 53 {
			return Err(InvalidSelector("BYWEEKNO"))
		}
	}
	for day in spec.by_day {
		if day.ordinal < -53 or day.ordinal > 53 {
			return Err(InvalidSelector("BYDAY"))
		}
		if day.ordinal != 0 and (spec.frequency == Daily or spec.frequency == Weekly or !spec.by_week_no.is_empty()) {
			return Err(InvalidCombination("ordinal BYDAY"))
		}
	}
	if spec.frequency == Weekly and !spec.by_month_day.is_empty() {
		return Err(InvalidCombination("BYMONTHDAY with WEEKLY"))
	}
	if spec.frequency != Yearly and !spec.by_year_day.is_empty() {
		return Err(InvalidCombination("BYYEARDAY requires YEARLY"))
	}
	if spec.frequency != Yearly and !spec.by_week_no.is_empty() {
		return Err(InvalidCombination("BYWEEKNO requires YEARLY"))
	}
	Ok({})
}

matches_filters : CalendarPattern.Spec, GregorianDate -> Try(Bool, [OutOfRange, ..])
matches_filters = |spec, date| {
	fields = GregorianDate.to_fields(date)
	day = number(date)
	weekday = weekday_number(day)
	length = match GregorianDate.days_in_month(fields.year, fields.month) {
		Ok(value) => value.to_i64()
		Err(_) => crash "Validated Gregorian date fields"
	}
	if !spec.by_month.is_empty() and !spec.by_month.contains(fields.month) {
		return Ok(False)
	}
	if !spec.by_month_day.is_empty() {
		var $found = False
		for selected in spec.by_month_day {
			$found = $found or ordinal_matches(selected.to_i64(), fields.day.to_i64(), length)
		}
		if !$found {
			return Ok(False)
		}
	}
	if !spec.by_year_day.is_empty() {
		first = number(january(fields.year.to_i128())?)
		last = first + year_length(fields.year)
		var $found = False
		for selected in spec.by_year_day {
			$found = $found or ordinal_matches(selected.to_i64(), day - first + 1, last - first)
		}
		if !$found {
			return Ok(False)
		}
	}
	if !spec.by_week_no.is_empty() {
		week = week_position(date, spec.week_start)?
		var $found = False
		for selected in spec.by_week_no {
			$found = $found or ordinal_matches(selected.to_i64(), week.position, week.total)
		}
		if !$found {
			return Ok(False)
		}
	}
	if !spec.by_day.is_empty() {
		var $found = False
		for selected in spec.by_day {
			if weekday_index(selected.weekday) == weekday {
				if selected.ordinal == 0 {
					$found = True
				} else {
					var $position = fields.day.to_i64()
					var $total = length
					# RFC 5545 verified erratum 3779: ordinal YEARLY BYDAY
					# is relative to the year only when BYMONTH is absent.
					if spec.frequency == Yearly and spec.by_month.is_empty() {
						first = number(january(fields.year.to_i128())?)
						last = first + year_length(fields.year)
						$position = day - first + 1
						$total = last - first
					}
					positive = I64.div_trunc_by($position - 1, 7) + 1
					negative = -(I64.div_trunc_by($total - $position, 7) + 1)
					$found = $found or selected.ordinal.to_i64() == positive or selected.ordinal.to_i64() == negative
				}
			}
		}
		if !$found {
			return Ok(False)
		}
	}

	Ok(True)
}

# Only called with a year from a validated date. Do not require a representable
# next January merely to filter a date in the final supported Gregorian year.
year_length = |year| match GregorianDate.days_in_month(year, 2) {
	Ok(february) => 337.I64 + february.to_i64()
	Err(_) => crash "validated Gregorian year"
}

expect {
	filter = CalendarPattern.Filter.new({ by_month: [], by_month_day: [], by_year_day: [-1], by_day: [] })?
	last = GregorianDate.from_fields({ year: 2147483647, month: 12, day: 31 })?
	first = GregorianDate.from_fields({ year: 2147483647, month: 1, day: 1 })?
	CalendarPattern.Filter.matches(filter, last)? and !CalendarPattern.Filter.matches(filter, first)?
}
