import SemanticFact
import Calendar
import FixedOffset
import PosixBoundary
import PosixSpan
import Coverage
import CalendarDate
import CivilDay
import ClockTime
import LocalDateTime
import ZoneRules

## A finite calendar selection retaining its supplied resolution and calendar.
## This native profile supports Gregorian/Julian provider years and 1–6 decimal
## fraction digits. It is not a timestamp parser or an uncertainty model.
## Minute 12:30 differs from second 12:30:00, and fraction .12 from .120.
## Canonical starts fill omitted lower fields solely to describe selection bounds.
## Construction is constant work and does not resolve zones or enumerate values.
## An exclusive upper boundary outside the provider range fails only at lowering.
CalendarValue :: { start : LocalDateTime, precision : Resolution }.{
	Resolution : [Year, Month, Day, Hour, Minute, Second, Fraction(U8)]

	year : Calendar, I64 -> Try(CalendarValue, [OutOfRange, InvalidMonth, InvalidDay, ..])
	year = |calendar, number| {
		date = CalendarDate.from_fields(calendar, { year: number, month: 1, day: 1 })?
		Ok({ start: midnight(date), precision: Year })
	}
	month : Calendar, I64, U8 -> Try(CalendarValue, [OutOfRange, InvalidMonth, InvalidDay, ..])
	month = |calendar, number, month_number| {
		date = CalendarDate.from_fields(calendar, { year: number, month: month_number, day: 1 })?
		Ok({ start: midnight(date), precision: Month })
	}
	day : CalendarDate -> CalendarValue
	day = |date| { start: midnight(date), precision: Day }
	hour : CalendarDate, U8 -> Try(CalendarValue, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	hour = |date, h| {
		clock = ClockTime.from_fields({ hour: h, minute: 0, second: 0, microsecond: 0 })?
		Ok({ start: LocalDateTime.new(date, clock), precision: Hour })
	}
	minute : CalendarDate, U8, U8 -> Try(CalendarValue, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	minute = |date, h, m| {
		clock = ClockTime.from_fields({ hour: h, minute: m, second: 0, microsecond: 0 })?
		Ok({ start: LocalDateTime.new(date, clock), precision: Minute })
	}
	second : CalendarDate, U8, U8, U8 -> Try(CalendarValue, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	second = |date, h, m, s| {
		clock = ClockTime.from_fields({ hour: h, minute: m, second: s, microsecond: 0 })?
		Ok({ start: LocalDateTime.new(date, clock), precision: Second })
	}

	## fraction is the supplied decimal integer: {value: 12, digits: 2} is .12.
	## Zero digits and values requiring more digits are malformed. More than six
	## digits are unsupported, even when trailing zeroes could be discarded.
	fractional_second : CalendarDate, { hour : U8, minute : U8, second : U8 }, { value : U32, digits : U8 } -> Try(CalendarValue, [InvalidFraction, UnsupportedPrecision, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	fractional_second = |date, clock_fields, fraction| {
		if fraction.digits == 0 {
			return Err(InvalidFraction)
		}
		if fraction.digits > 6 {
			return Err(UnsupportedPrecision)
		}
		width = fraction_width(fraction.digits)
		if fraction.value.to_i64() >= 1000000 // width {
			return Err(InvalidFraction)
		}
		# The checked fraction domain proves product <= 999999.
		micros = (fraction.value.to_i64() * width).to_u32_wrap()
		clock = ClockTime.from_fields({ hour: clock_fields.hour, minute: clock_fields.minute, second: clock_fields.second, microsecond: micros })?
		Ok({ start: LocalDateTime.new(date, clock), precision: Fraction(fraction.digits) })
	}
	resolution : CalendarValue -> Resolution
	resolution = |value| value.precision
	start_label : CalendarValue -> LocalDateTime
	start_label = |value| value.start

	## Half-open civil selection. O(1), with no zone choice or elapsed-time claim.
	## Year/month bounds use Gregorian/Julian's twelve-month shape explicitly.
	local_bounds : CalendarValue -> Try({ start : LocalDateTime, end : LocalDateTime }, [OutOfRange, ..])
	local_bounds = |value| {
		date = LocalDateTime.date(value.start)
		calendar = CalendarDate.calendar(date)
		end = match value.precision {
			Year => {
				fields = CalendarDate.to_fields(date)
				following = checked_date(calendar, { year: fields.year + 1, month: 1, day: 1 })?
				midnight(following)
			}
			Month => {
				fields = CalendarDate.to_fields(date)
				following = if fields.month == 12 {
					checked_date(calendar, { year: fields.year + 1, month: 1, day: 1 })?
				} else {
					checked_date(calendar, { year: fields.year, month: fields.month + 1, day: 1 })?
				}
				midnight(following)
			}
			other => {
				width = match other {
					Day => 86400000000.I64
					Hour => 3600000000
					Minute => 60000000
					Second => 1000000
					Fraction(digits) => fraction_width(digits)
					_ => crash "Year/month handled above"
				}
				# Constructor alignment means this can only reach, not cross,
				# next midnight. All arithmetic is bounded by two civil days.
				total = ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(value.start)) + width
				if total == 86400000000 {
					next_day = CivilDay.to_day_number(CalendarDate.to_civil_day(date)) + 1
					following = CalendarDate.from_civil_day(calendar, CivilDay.from_day_number(next_day))?
					midnight(following)
				} else {
					LocalDateTime.new(date, checked_clock(total))
				}
			}
		}
		Ok({ start: value.start, end })
	}

	## Resolve the entire local selection, including all fold components and
	## empty gaps. Uses the shared bounded cursor; no earliest/latest envelope.
	## Cursor construction does not consume the transition table. Explicit
	## SelectionLimits govern subsequent ZoneRules.SelectionCursor.collect calls.
	selection_cursor : CalendarValue, ZoneRules -> Try(ZoneRules.SelectionCursor, [OutOfRange, EmptySelection, ReversedSelection, OutsideValidity, ..])
	selection_cursor = |value, rules| {
		bounds = local_bounds(value)?
		ZoneRules.selection_cursor(rules, bounds.start, bounds.end)
	}

	## Description equality, including precision and calendar identity.
	is_eq : CalendarValue, CalendarValue -> Bool
	is_eq = |a, b| a.start == b.start and a.precision == b.precision
	to_hash : CalendarValue, Hasher -> Hasher
	to_hash = |value, hasher| {
		code = match value.precision {
			Year => 0.U8
			Month => 1
			Day => 2
			Hour => 3
			Minute => 4
			Second => 5
			Fraction(digits) => 5 + digits
		}
		code.to_hash(value.start.to_hash(hasher))
	}

	## Constant-cost random-access observations; no selection is resolved.
	fact_count : CalendarValue -> U64
	fact_count = |_| 2
	fact_at : CalendarValue, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| match index {
		0 => {
			date = LocalDateTime.date(value.start)
			Item(SemanticFact.new(CalendarDescription({ kind: CalendarValue, calendar: CalendarDate.calendar(date), fields: CalendarDate.to_fields(date), clock: ClockTime.to_fields(LocalDateTime.clock(value.start)), resolution: value.precision, qualification_count: 0 })))
		}
		1 => Item(SemanticFact.new(Requirement(ZoneContext)))
		_ => End
	}
	to_inspect : CalendarValue -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "CalendarValue always has a summary fact at index zero"
	}
}

# Both current providers have I32 years and twelve months. Validated selections
# use only day one in year/month succession, so a failure is a provider limit.
checked_date = |calendar, fields| match CalendarDate.from_fields(calendar, fields) {
	Ok(date) => Ok(date)
	Err(_) => Err(OutOfRange)
}

midnight = |date| LocalDateTime.new(date, checked_clock(0))

checked_clock = |number| match ClockTime.from_microseconds_since_midnight(number) {
	Ok(value) => value
	Err(_) => crash "Aligned calendar selection clock invariant"
}

fraction_width = |digits| match digits {
	1 => 100000.I64
	2 => 10000
	3 => 1000
	4 => 100
	5 => 10
	6 => 1
	_ => crash "Validated decimal resolution invariant"
}

expect {
	date = CalendarDate.from_fields(Gregorian, { year: 2024, month: 2, day: 29 })?
	minute = CalendarValue.minute(date, 12, 30)?
	second = CalendarValue.second(date, 12, 30, 0)?
	a = CalendarValue.fractional_second(date, { hour: 12, minute: 30, second: 0 }, { value: 12, digits: 2 })?
	b = CalendarValue.fractional_second(date, { hour: 12, minute: 30, second: 0 }, { value: 120, digits: 3 })?
	minute != second and a != b and CalendarValue.start_label(minute) == CalendarValue.start_label(second) and
		CalendarValue.start_label(a) == CalendarValue.start_label(b) and
			CalendarValue.local_bounds(a)?.end != CalendarValue.local_bounds(b)?.end
}
expect {
	# Independent calendar fact: Gregorian 1900 is common, Julian 1900 leap.
	gregorian = CalendarValue.local_bounds(CalendarValue.month(Gregorian, 1900, 2)?)?
	julian = CalendarValue.local_bounds(CalendarValue.month(Julian, 1900, 2)?)?
	test_days(gregorian) == 28 and test_days(julian) == 29
}
expect {
	last = CalendarDate.from_fields(Gregorian, { year: 2147483647, month: 12, day: 31 })?
	tiny = CalendarValue.fractional_second(last, { hour: 23, minute: 59, second: 59 }, { value: 999999, digits: 6 })?
	CalendarValue.local_bounds(tiny) == Err(OutOfRange) and
		CalendarValue.local_bounds(CalendarValue.year(Gregorian, 2147483647)?) == Err(OutOfRange) and
			CalendarValue.local_bounds(CalendarValue.month(Gregorian, 2147483647, 12)?) == Err(OutOfRange)
}
expect {
	date = CalendarDate.from_fields(Gregorian, { year: 2024, month: 1, day: 1 })?
	fields = { hour: 0, minute: 0, second: 0 }
	CalendarValue.fractional_second(date, fields, { value: 1200000, digits: 7 }) == Err(UnsupportedPrecision) and
		CalendarValue.fractional_second(date, fields, { value: 0, digits: 0 }) == Err(InvalidFraction) and
			CalendarValue.fractional_second(date, fields, { value: 100, digits: 2 }) == Err(InvalidFraction) and
				CalendarValue.minute(date, 24, 0) == Err(InvalidHour) and
					CalendarValue.second(date, 23, 59, 60) == Err(UnsupportedLeapSecond) and
						CalendarValue.month(Gregorian, 2024, 13) == Err(InvalidMonth) and
							CalendarValue.year(Gregorian, I64.highest) == Err(OutOfRange)
}
test_days = |bounds| CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(bounds.end))) - CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(bounds.start)))

expect {
	date = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
	value = CalendarValue.fractional_second(date, { hour: 0, minute: 0, second: 0 }, { value: 12, digits: 2 })?
	rules = ZoneRules.new_bounded("Synthetic/FractionFold", "v1", test_span(-4000000, 4000000)?, FixedOffset.from_seconds(2), [{ at: PosixBoundary.from_microseconds(-1000000), offset: FixedOffset.from_seconds(0) }], { minimum: 0, maximum: 2 })?
	cursor = CalendarValue.selection_cursor(value, rules)?
	batch = ZoneRules.SelectionCursor.collect(cursor, { max_segments: 2, max_members: 2 })?
	match batch.status {
		Complete(coverage) => coverage == Coverage.from_spans([test_span(-1880000, -1870000)?, test_span(120000, 130000)?])
		Limited(_) => False
	}
}
expect {
	zero = FixedOffset.from_seconds(0)
	last = FixedOffset.project(zero, PosixBoundary.from_microseconds(I64.highest), Gregorian)?
	fields = ClockTime.to_fields(LocalDateTime.clock(last))
	value = CalendarValue.fractional_second(LocalDateTime.date(last), { hour: fields.hour, minute: fields.minute, second: fields.second }, { value: fields.microsecond, digits: 6 })?
	rules = ZoneRules.new_bounded("UTC", "v1", test_span(I64.lowest, I64.highest)?, zero, [], { minimum: 0, maximum: 0 })?
	# The civil successor fits, but its POSIX upper boundary does not.
	_ = CalendarValue.local_bounds(value)?
	match CalendarValue.selection_cursor(value, rules) {
		Err(OutOfRange) => True
		_ => False
	}
}
test_span = |start, end| PosixSpan.new(PosixBoundary.from_microseconds(start), PosixBoundary.from_microseconds(end))

expect {
	date = CalendarDate.from_fields(Gregorian, { year: 2004, month: 6, day: 11 })?
	minute = CalendarValue.minute(date, 12, 30)?
	second = CalendarValue.second(date, 12, 30, 0)?
	short = CalendarValue.fractional_second(date, { hour: 12, minute: 30, second: 0 }, { digits: 2, value: 12 })?
	long = CalendarValue.fractional_second(date, { hour: 12, minute: 30, second: 0 }, { digits: 3, value: 120 })?
	CalendarValue.fact_at(minute, 0) != CalendarValue.fact_at(second, 0) and
		CalendarValue.fact_at(short, 0) != CalendarValue.fact_at(long, 0) and
			Str.inspect(short).contains(".12,") and Str.inspect(long).contains(".120,") and
				CalendarValue.fact_count(minute) == 2 and CalendarValue.fact_at(minute, 2) == End and CalendarValue.fact_at(minute, U64.highest) == End
}
