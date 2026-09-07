import ClockTime
import CalendarDescriptionText
import CivilDay
import GregorianDate
import JulianDate

## Calendar profiles and their related dates, quantities and selections.
## Date retains calendar identity; Delta describes calendar components;
## Value retains supplied resolution. Arithmetic requires an explicit policy.
## Gregorian and Julian profiles are proleptic; no historical reform is inferred.
Calendar := [Gregorian, Julian].{

	## Gregorian date arithmetic with explicit invalid-date policy.
	## Components apply in year/month/day order; this is not recurrence expansion.
	## For January 31 plus one month, Clamp chooses February's last day;
	## Reject returns InvalidDestination, and Carry moves excess days into March.
	## Work is constant, without zone resolution. Provider limits return OutOfRange.
	Arithmetic :: [].{
		Policy : [Reject, Clamp, Carry]

		shift_day : GregorianDate, Calendar.Delta, Policy -> Try(GregorianDate, [OutOfRange, InvalidDestination(GregorianDate.Fields), ..])
		shift_day = |date, delta, policy| {
			parts = Calendar.Delta.to_components(delta)
			fields = GregorianDate.to_fields(date)
			# Explicit mapping preserves the structured error contract on the pinned
			# interpreter; see tests/compiler_repro/result_widening/README.md.
			year = match arithmetic_narrow_year(I64.to_i128(fields.year) + I64.to_i128(parts.years)) {
				Ok(value) => value
				Err(OutOfRange) => return Err(OutOfRange)
			}
			after_years = arithmetic_destination(year, fields.month, fields.day, policy)?
			after_year_fields = GregorianDate.to_fields(after_years)
			# Gregorian alone has exactly twelve months per year. This is not a
			# generic calendar-provider equivalence between years and months.
			index = I64.to_i128(after_year_fields.year) * 12 + U8.to_i128(after_year_fields.month) - 1 + I64.to_i128(parts.months)
			month_year = match arithmetic_narrow_year(I128.div_floor_by(index, 12)) {
				Ok(value) => value
				Err(OutOfRange) => return Err(OutOfRange)
			}
			month = match I128.to_u8_try(I128.mod_by(index, 12) + 1) {
				Ok(value) => value
				Err(_) => crash "Gregorian month remainder invariant"
			}
			after_months = arithmetic_destination(month_year, month, after_year_fields.day, policy)?
			arithmetic_shift_days(after_months, parts.days)
		}

		expect {
			issued = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
			clamped = shift_day(issued, Calendar.Delta.months(1), Clamp)?
			GregorianDate.to_fields(clamped) == { year: 2025, month: 2, day: 28 } and
				shift_day(issued, Calendar.Delta.months(1), Reject) == Err(InvalidDestination({ year: 2025, month: 2, day: 31 })) and
					GregorianDate.to_fields(shift_day(issued, Calendar.Delta.months(1), Carry)?) == { year: 2025, month: 3, day: 3 } and
						GregorianDate.to_fields(shift_day(clamped, Calendar.Delta.months(-1), Clamp)?) == { year: 2025, month: 1, day: 28 }
		}

		expect {
			leap_day = GregorianDate.from_fields({ year: 2020, month: 2, day: 29 })?
			ordered = Calendar.Delta.from_components({ years: 1, months: 1, days: 1 })
			GregorianDate.to_fields(shift_day(leap_day, ordered, Clamp)?) == { year: 2021, month: 3, day: 29 }
		}

		expect {
			january = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
			zero = GregorianDate.from_fields({ year: 0, month: 1, day: 31 })?
			# A two-month component has one destination; it does not clamp in February.
			GregorianDate.to_fields(shift_day(january, Calendar.Delta.months(2), Clamp)?) == { year: 2025, month: 3, day: 31 } and
				GregorianDate.to_fields(shift_day(zero, Calendar.Delta.months(-1), Reject)?) == { year: -1, month: 12, day: 31 }
		}

		expect {
			first = GregorianDate.from_fields({ year: -2147483648, month: 1, day: 1 })?
			last = GregorianDate.from_fields({ year: 2147483647, month: 12, day: 31 })?
			shift_day(first, Calendar.Delta.days(-1), Clamp) == Err(OutOfRange) and
				shift_day(last, Calendar.Delta.days(1), Clamp) == Err(OutOfRange) and
					shift_day(first, Calendar.Delta.months(I64.lowest), Carry) == Err(OutOfRange) and
						shift_day(last, Calendar.Delta.years(I64.highest), Reject) == Err(OutOfRange) and
							shift_day(last, Calendar.Delta.from_components({ years: 1, months: -12, days: 0 }), Clamp) == Err(OutOfRange)
		}
	}

	is_eq : Calendar, Calendar -> Bool
	is_eq = |a, b| to_name(a) == to_name(b)

	to_hash : Calendar, Hasher -> Hasher
	to_hash = |calendar, hasher| to_name(calendar).to_hash(hasher)

	to_inspect : Calendar -> Str
	to_inspect = |calendar| "Calendar(${to_name(calendar)})"
	from_name : Str -> Try(Calendar, [UnsupportedCalendar(Str), ..])
	from_name = |name| {
		match name {
			"gregorian" => Ok(Gregorian)
			"julian" => Ok(Julian)
			_ => Err(UnsupportedCalendar(name))
		}
	}

	to_name : Calendar -> Str
	to_name = |calendar| match calendar {
		Gregorian => "gregorian"
		Julian => "julian"
	}

	## A validated day description retaining its calendar. Resolution is one civil day.
	Date :: [Gregorian(GregorianDate), Julian(JulianDate)].{
		Fields : { year : I64, month : U8, day : U8 }

		## Preserve an already validated date and its calendar without revalidation.
		from_gregorian : GregorianDate -> Date
		from_gregorian = |date| Gregorian(date)
		from_julian : JulianDate -> Date
		from_julian = |date| Julian(date)

		## Access a stored Gregorian date without converting another calendar.
		## Use in_calendar when conversion, rather than access, is intended.
		as_gregorian : Date -> Try(GregorianDate, [UnsupportedCalendar(Calendar), ..])
		as_gregorian = |date| match date {
			Gregorian(value) => Ok(value)
			Julian(_) => Err(UnsupportedCalendar(Julian))
		}

		from_fields : Calendar, Fields -> Try(Date, [OutOfRange, InvalidMonth, InvalidDay, ..])
		from_fields = |calendar, fields| match calendar {
			Gregorian => match GregorianDate.from_fields(fields) {
				Ok(date) => Ok(Gregorian(date))
				Err(error) => Err(error)
			}
			Julian => match JulianDate.from_fields(fields) {
				Ok(date) => Ok(Julian(date))
				Err(error) => Err(error)
			}
		}

		from_civil_day : Calendar, CivilDay -> Try(Date, [OutOfRange, ..])
		from_civil_day = |calendar, coordinate| match calendar {
			Gregorian => match GregorianDate.from_civil_day(coordinate) {
				Ok(date) => Ok(Gregorian(date))
				Err(error) => Err(error)
			}
			Julian => match JulianDate.from_civil_day(coordinate) {
				Ok(date) => Ok(Julian(date))
				Err(error) => Err(error)
			}
		}

		to_civil_day : Date -> CivilDay
		to_civil_day = |date| match date {
			Gregorian(value) => GregorianDate.to_civil_day(value)
			Julian(value) => JulianDate.to_civil_day(value)
		}

		calendar : Date -> Calendar
		calendar = |date| match date {
			Gregorian(_) => Gregorian
			Julian(_) => Julian
		}

		to_fields : Date -> Fields
		to_fields = |date| match date {
			Gregorian(value) => GregorianDate.to_fields(value)
			Julian(value) => JulianDate.to_fields(value)
		}

		in_calendar : Date, Calendar -> Try(Date, [OutOfRange, ..])
		in_calendar = |date, target| from_civil_day(target, to_civil_day(date))

		## Equal day extent on the shared civil axis, independent of description.
		same_day : Date, Date -> Bool
		same_day = |a, b| to_civil_day(a) == to_civil_day(b)

		## Description equality retains calendar identity; use same_day for extents.
		is_eq : Date, Date -> Bool
		is_eq = |a, b| match (a, b) {
			(Gregorian(left), Gregorian(right)) => left == right
			(Julian(left), Julian(right)) => left == right
			_ => Bool.False
		}

		to_hash : Date, Hasher -> Hasher
		to_hash = |date, hasher| match date {
			Gregorian(value) => value.to_hash((0.U8).to_hash(hasher))
			Julian(value) => value.to_hash((1.U8).to_hash(hasher))
		}

		to_inspect : Date -> Str
		to_inspect = |date| match date {
			Gregorian(value) => Str.inspect(value)
			Julian(value) => Str.inspect(value)
		}

		expect {
			# Independent equal-day anchor: Hinnant's Julian conversion derivation,
			# https://howardhinnant.github.io/date_algorithms.html (2021-09-01).
			julian = from_fields(Julian, { year: 1582, month: 10, day: 5 })?
			gregorian = from_fields(Gregorian, { year: 1582, month: 10, day: 15 })?
			same_day(julian, gregorian) and julian != gregorian and
				in_calendar(julian, Gregorian) == Ok(gregorian)
		}

		expect Calendar.from_name("hebrew") == Err(UnsupportedCalendar("hebrew"))
		expect {
			outer = from_fields(Julian, { year: 2147483647, month: 12, day: 31 })?
			in_calendar(outer, Gregorian) == Err(OutOfRange)
		}
	}

	## Ordered calendar components, not an elapsed or POSIX displacement.
	## Arithmetic applies years, then months, then civil days.
	Delta :: [Parts({ years : I64, months : I64, days : I64 })].{
		Components : { years : I64, months : I64, days : I64 }
		from_components : Components -> Delta
		from_components = |components| Parts(components)
		to_components : Delta -> Components
		to_components = |Parts(components)| components

		## Compare component definitions without an anchor; one year is not twelve months.
		is_eq : Delta, Delta -> Bool
		is_eq = |Parts(a), Parts(b)| a == b
		to_hash : Delta, Hasher -> Hasher
		to_hash = |Parts(components), hasher| components.to_hash(hasher)

		## Bounded component description; no anchor, normalization or elapsed claim.
		to_inspect : Delta -> Str
		to_inspect = |Parts(components)| "Calendar.Delta(years=${components.years.to_str()}, months=${components.months.to_str()}, days=${components.days.to_str()})"

		expect Str.inspect(from_components({ years: -1, months: 12, days: 0 })) == "Calendar.Delta(years=-1, months=12, days=0)"

		expect {
			year = years(1)
			same = from_components({ years: 1, months: 0, days: 0 })
			month = months(12)
			values = Dict.insert(Dict.insert(Dict.empty(), year, 1.U8), month, 2)
			year == same and year != month and Dict.get(values, same) == Ok(1) and Dict.get(values, month) == Ok(2)
		}

		years : I64 -> Delta
		years = |n| Parts({ years: n, months: 0, days: 0 })
		months : I64 -> Delta
		months = |n| Parts({ years: 0, months: n, days: 0 })
		days : I64 -> Delta
		days = |n| Parts({ years: 0, months: 0, days: n })
	}

	## A finite civil selection retaining its calendar and supplied resolution.
	## Supports Gregorian/Julian provider years and one to six fractional digits.
	## Minute 12:30 differs from second 12:30:00; .12 differs from .120.
	## Construction validates once in constant work, without choosing a zone or
	## computing an exclusive upper bound. Bounds outside the provider range
	## fail only when requested. Use ZoneRules.calendar_selection_cursor for
	## bounded interpretation, preserving disconnected folds and empty gaps.
	Value :: { start : { date : Calendar.Date, clock : ClockTime }, precision : Resolution }.{

		Resolution : [Year, Month, Day, Hour, Minute, Second, Fraction(U8)]

		## Select the whole provider year; year zero is 1 BCE.
		year : Calendar, I64 -> Try(Value, [OutOfRange, InvalidMonth, InvalidDay, ..])
		year = |calendar, number| {
			date = Calendar.Date.from_fields(calendar, { year: number, month: 1, day: 1 })?
			Ok({ start: value_midnight(date), precision: Year })
		}

		## Select a whole calendar month; invalid month numbers return InvalidMonth.
		month : Calendar, I64, U8 -> Try(Value, [OutOfRange, InvalidMonth, InvalidDay, ..])
		month = |calendar, number, month_number| {
			date = Calendar.Date.from_fields(calendar, { year: number, month: month_number, day: 1 })?
			Ok({ start: value_midnight(date), precision: Month })
		}

		## Select one validated civil date; no fixed elapsed duration is implied.
		day : Calendar.Date -> Value
		day = |date| { start: value_midnight(date), precision: Day }
		hour : Calendar.Date, U8 -> Try(Value, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
		hour = |date, h| {
			clock = ClockTime.from_fields({ hour: h, minute: 0, second: 0, microsecond: 0 })?
			Ok({ start: { date, clock }, precision: Hour })
		}
		minute : Calendar.Date, U8, U8 -> Try(Value, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
		minute = |date, h, m| {
			clock = ClockTime.from_fields({ hour: h, minute: m, second: 0, microsecond: 0 })?
			Ok({ start: { date, clock }, precision: Minute })
		}
		second : Calendar.Date, U8, U8, U8 -> Try(Value, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
		second = |date, h, m, s| {
			clock = ClockTime.from_fields({ hour: h, minute: m, second: s, microsecond: 0 })?
			Ok({ start: { date, clock }, precision: Second })
		}

		## fraction is the supplied decimal integer: {value: 12, digits: 2} is .12.
		## Zero digits and values requiring more digits are malformed. More than six
		## digits are unsupported, even when trailing zeroes could be discarded.
		fractional_second : Calendar.Date, { hour : U8, minute : U8, second : U8 }, { value : U32, digits : U8 } -> Try(Value, [InvalidFraction, UnsupportedPrecision, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
		fractional_second = |date, clock_fields, fraction| {
			if fraction.digits == 0 {
				return Err(InvalidFraction)
			}
			if fraction.digits > 6 {
				return Err(UnsupportedPrecision)
			}
			width = value_fraction_width(fraction.digits)
			if fraction.value.to_i64() >= 1000000 // width {
				return Err(InvalidFraction)
			}
			# The checked fraction domain proves product <= 999999.
			micros = (fraction.value.to_i64() * width).to_u32_wrap()
			clock = ClockTime.from_fields({ hour: clock_fields.hour, minute: clock_fields.minute, second: clock_fields.second, microsecond: micros })?
			Ok({ start: { date, clock }, precision: Fraction(fraction.digits) })
		}

		## Supplied field precision, preserved even when lower fields are zero.
		resolution : Value -> Resolution
		resolution = |value| value.precision

		## Canonical start components; omitted lower fields are filled only for bounds.
		## Their presence does not mean the caller supplied a complete local label.
		date : Value -> Calendar.Date
		date = |value| value.start.date

		## Canonical start clock; pair with date only for explicit label composition.
		clock : Value -> ClockTime
		clock = |value| value.start.clock

		## Half-open civil selection. O(1), with no zone choice or elapsed-time claim.
		## Year/month bounds use Gregorian/Julian's twelve-month shape explicitly.
		bounds : Value -> Try({ start : { date : Calendar.Date, clock : ClockTime }, end : { date : Calendar.Date, clock : ClockTime } }, [OutOfRange, ..])
		bounds = |value| {
			selected_date = value.start.date
			calendar = Calendar.Date.calendar(selected_date)
			end = match value.precision {
				Year => {
					fields = Calendar.Date.to_fields(selected_date)
					following = value_checked_date(calendar, { year: fields.year + 1, month: 1, day: 1 })?
					value_midnight(following)
				}
				Month => {
					fields = Calendar.Date.to_fields(selected_date)
					following = if fields.month == 12 {
						value_checked_date(calendar, { year: fields.year + 1, month: 1, day: 1 })?
					} else {
						value_checked_date(calendar, { year: fields.year, month: fields.month + 1, day: 1 })?
					}
					value_midnight(following)
				}
				other => {
					width = match other {
						Day => 86400000000.I64
						Hour => 3600000000
						Minute => 60000000
						Second => 1000000
						Fraction(digits) => value_fraction_width(digits)
						_ => crash "Year/month handled above"
					}
					# Constructor alignment means this can only reach, not cross,
					# next midnight. All arithmetic is bounded by two civil days.
					total = ClockTime.to_microseconds_since_midnight(value.start.clock) + width
					if total == 86400000000 {
						next_day = CivilDay.to_day_number(Calendar.Date.to_civil_day(selected_date)) + 1
						following = Calendar.Date.from_civil_day(calendar, CivilDay.from_day_number(next_day))?
						value_midnight(following)
					} else {
						{ date: selected_date, clock: value_checked_clock(total) }
					}
				}
			}
			Ok({ start: value.start, end })
		}

		## Description equality, including precision and calendar identity.
		is_eq : Value, Value -> Bool
		is_eq = |a, b| a.start == b.start and a.precision == b.precision
		to_hash : Value, Hasher -> Hasher
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
			code.to_hash(value.start.clock.to_hash(value.start.date.to_hash(hasher)))
		}

		## Supplied description metadata, without lowering or interpretation.
		Description : { calendar : Calendar, fields : Calendar.Date.Fields, clock : ClockTime.Fields, resolution : Resolution }
		description : Value -> Description
		description = |value| { calendar: Calendar.Date.calendar(value.start.date), fields: Calendar.Date.to_fields(value.start.date), clock: ClockTime.to_fields(value.start.clock), resolution: value.precision }
		to_inspect : Value -> Str
		to_inspect = |value| {
			data = description(value)
			CalendarDescriptionText.summary({ kind: CalendarValue, calendar: Calendar.to_name(data.calendar), fields: data.fields, clock: data.clock, resolution: data.resolution, qualification_count: 0.U64 })
		}
	}
}

# Both current providers have I32 years and twelve months. Validated selections
# use only day one in year/month succession, so a failure is a provider limit.
value_checked_date = |calendar, fields| match Calendar.Date.from_fields(calendar, fields) {
	Ok(date) => Ok(date)
	Err(_) => Err(OutOfRange)
}

value_midnight = |date| { date, clock: value_checked_clock(0) }

value_checked_clock = |number| match ClockTime.from_microseconds_since_midnight(number) {
	Ok(value) => value
	Err(_) => crash "Aligned calendar selection clock invariant"
}

value_fraction_width = |digits| match digits {
	1 => 100000.I64
	2 => 10000
	3 => 1000
	4 => 100
	5 => 10
	6 => 1
	_ => crash "Validated decimal resolution invariant"
}

arithmetic_narrow_year : I128 -> Try(I64, [OutOfRange, ..])
arithmetic_narrow_year = |year| {
	if year < -2147483648 or year > 2147483647 {
		return Err(OutOfRange)
	}
	I128.to_i64_try(year)
}

arithmetic_destination : I64, U8, U8, Calendar.Arithmetic.Policy -> Try(GregorianDate, [OutOfRange, InvalidDestination(GregorianDate.Fields), ..])
arithmetic_destination = |year, month, day, policy| {
	length = match GregorianDate.days_in_month(year, month) {
		Ok(value) => value
		Err(OutOfRange) => return Err(OutOfRange)
		Err(InvalidMonth) => crash "Gregorian arithmetic month invariant"
	}
	if day > length and policy == Reject {
		return Err(InvalidDestination({ year, month, day }))
	}
	chosen = if day > length {
		length
	} else {
		day
	}
	valid = match GregorianDate.from_fields({ year, month, day: chosen }) {
		Ok(value) => value
		Err(_) => crash "Gregorian arithmetic arithmetic_destination invariant"
	}
	if day > length and policy == Carry {
		arithmetic_shift_days(valid, U8.to_i64(day - length))
	} else {
		Ok(valid)
	}
}

arithmetic_shift_days : GregorianDate, I64 -> Try(GregorianDate, [OutOfRange, ..])
arithmetic_shift_days = |date, days| {
	start = CivilDay.to_day_number(GregorianDate.to_civil_day(date))
	number = match I64.plus_try(start, days) {
		Ok(value) => value
		Err(Overflow) => return Err(OutOfRange)
	}
	GregorianDate.from_civil_day(CivilDay.from_day_number(number))
}
