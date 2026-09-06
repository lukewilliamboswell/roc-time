import CivilDay

## Proleptic Gregorian day, with astronomical years (0 means 1 BCE).
## Valid years are -2147483648 through 2147483647, inclusive.
## No timezone or resolved timeline is implied by a date.
##
## Example
##
## Create a date and read its fields. Invalid leap days return `InvalidDay`;
## year zero and negative years use astronomical numbering.
##
## ```roc
## import time.GregorianDate
##
## expect {
##     date = GregorianDate.from_fields({ year: 2024, month: 2, day: 29 })?
##     GregorianDate.to_fields(date).day == 29
## }
## expect {
##     invalid = GregorianDate.from_fields({ year: 2025, month: 2, day: 29 })
##     invalid == Err(InvalidDay)
## }
## ```
##
## Examples assume a package dependency named `time`.
GregorianDate :: [Date({ year : I64, month : U8, day : U8 })].{
	Fields : { year : I64, month : U8, day : U8 }

	from_fields : Fields -> Try(GregorianDate, [OutOfRange, InvalidMonth, InvalidDay, ..])
	from_fields = |fields| {
		length = days_in_month(fields.year, fields.month)?
		if fields.day < 1 or fields.day > length {
			return Err(InvalidDay)
		}
		Ok(Date(fields))
	}

	days_in_month : I64, U8 -> Try(U8, [OutOfRange, InvalidMonth, ..])
	days_in_month = |year, month| {
		if year < -2147483648 or year > 2147483647 {
			return Err(OutOfRange)
		}
		if month < 1 or month > 12 {
			return Err(InvalidMonth)
		}
		Ok(month_length(year, month))
	}

	to_fields : GregorianDate -> Fields
	to_fields = |Date(fields)| fields

	to_civil_day : GregorianDate -> CivilDay
	to_civil_day = |Date(date)| {
		# Common-year days preceding each month. Nominal construction establishes
		# month 1..12; only dates after February need a leap-day correction.
		before = match date.month {
			1 => 0.I64
			2 => 31
			3 => 59
			4 => 90
			5 => 120
			6 => 151
			7 => 181
			8 => 212
			9 => 243
			10 => 273
			11 => 304
			_ => 334
		}
		leap_day = if date.month > 2 and month_length(date.year, 2) == 29 {
			1.I64
		} else {
			0.I64
		}
		CivilDay.from_day_number(year_start(date.year) + before + leap_day + U8.to_i64(date.day) - 1)
	}

	from_civil_day : CivilDay -> Try(GregorianDate, [OutOfRange, ..])
	from_civil_day = |day| {
		number = CivilDay.to_day_number(day)
		if number < year_start(-2147483648) or number >= year_start(2147483648) {
			return Err(OutOfRange)
		}
		# March-based Gregorian eras, adapted from Howard Hinnant's
		# civil_from_days (2021-09-01), donated to the public domain:
		# https://howardhinnant.github.io/date_algorithms.html#civil_from_days
		# Validate before shifting: arbitrary CivilDay inputs may be I64 extremes.
		# The provider range keeps every intermediate within I64.
		shifted = number + 719468
		era = I64.div_floor_by(shifted, 146097)
		# Floor division leaves a nonnegative era remainder, even for negative
		# years. Only this bounded remainder is narrowed: era/year stay I64.
		era_day = match I64.to_u32_try(shifted - era * 146097) {
			Ok(value) => value # 0..146096
			Err(_) => crash "Gregorian era remainder invariant"
		}
		# era_year is 0..399; year_day is 0..365; march_month is 0..11.
		# All unsigned subtractions are nonnegative in this decomposition.
		# Its largest intermediate is below 2^18, safely inside U32.
		era_year = (era_day - era_day // 1460 + era_day // 36524 - era_day // 146096) // 365
		year_day = era_day - (365 * era_year + era_year // 4 - era_year // 100)
		march_month = (5 * year_day + 2) // 153
		month_number = if march_month < 10 {
			march_month + 3
		} else {
			march_month - 9
		}
		day_number = year_day - (153 * march_month + 2) // 5 + 1
		year = era * 400 + era_year.to_i64() + if month_number <= 2 {
			1
		} else {
			0
		}
		# The decomposition guarantees month 1..12 and day 1..31.
		month = match U32.to_u8_try(month_number) {
			Ok(value) => value
			Err(_) => crash "Gregorian month decomposition invariant"
		}
		day_of_month = match U32.to_u8_try(day_number) {
			Ok(value) => value
			Err(_) => crash "Gregorian day decomposition invariant"
		}
		Ok(Date({ year, month, day: day_of_month }))
	}

	to_hash : GregorianDate, Hasher -> Hasher
	to_hash = |Date(fields), hasher| fields.day.to_hash(fields.month.to_hash(fields.year.to_hash(hasher)))

	to_inspect : GregorianDate -> Str
	to_inspect = |Date(fields)| "GregorianDate(${fields.year.to_str()}, ${fields.month.to_str()}, ${fields.day.to_str()})"

	is_lt : GregorianDate, GregorianDate -> Bool
	is_lt = |a, b| to_civil_day(a) < to_civil_day(b)

	is_lte : GregorianDate, GregorianDate -> Bool
	is_lte = |a, b| to_civil_day(a) <= to_civil_day(b)

	is_gt : GregorianDate, GregorianDate -> Bool
	is_gt = |a, b| to_civil_day(a) > to_civil_day(b)

	is_gte : GregorianDate, GregorianDate -> Bool
	is_gte = |a, b| to_civil_day(a) >= to_civil_day(b)

	is_eq : GregorianDate, GregorianDate -> Bool
	is_eq = |Date(a), Date(b)| a.year == b.year and a.month == b.month and a.day == b.day

	expect from_civil_day(CivilDay.from_day_number(I64.lowest)) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(I64.highest)) == Err(OutOfRange)
	expect from_fields({ year: 1900, month: 2, day: 29 }) == Err(InvalidDay)
	expect from_fields({ year: 2000, month: 0, day: 1 }) == Err(InvalidMonth)
	expect from_fields({ year: 2147483648, month: 1, day: 1 }) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(-784353015834)) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(784351576777)) == Err(OutOfRange)
	expect {
		var valid = Bool.True
		for fixture in [
			{ fields: { year: 1970.I64, month: 1.U8, day: 1.U8 }, number: 0.I64 },
			{ fields: { year: 1, month: 1, day: 1 }, number: -719162 },
			{ fields: { year: 0, month: 1, day: 1 }, number: -719528 },
			{ fields: { year: 0, month: 2, day: 29 }, number: -719469 },
			{ fields: { year: -2147483648, month: 1, day: 1 }, number: -784353015833 },
			{ fields: { year: 2147483647, month: 12, day: 31 }, number: 784351576776 },
		] {
			date = from_fields(fixture.fields)
			coordinate = CivilDay.from_day_number(fixture.number)
			valid = valid and from_civil_day(coordinate) == date
			valid = valid and match date {
				Ok(value) => CivilDay.is_eq(to_civil_day(value), coordinate)
				Err(_) => Bool.False
			}
		}
		valid
	}
}

# Counts complete years before January 1 relative to Gregorian 1970-01-01.
# All callers constrain year to [-2147483648, 2147483648]; intermediates fit I64.
# Floor division, including before year zero, counts Gregorian leap years.
year_start : I64 -> I64
year_start = |year| {
	previous = year - 1
	365 * previous + I64.div_floor_by(previous, 4) - I64.div_floor_by(previous, 100) + I64.div_floor_by(previous, 400) - 719162
}

# Internal callers establish a valid year and month in 1..12.
month_length : I64, U8 -> U8
month_length = |year, month| {
	match month {
		2 => if I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0) {
			29
		} else {
			28
		}
		4 | 6 | 9 | 11 => 30
		_ => 31
	}
}

## R05: enumerate a complete Gregorian cycle independently of year-counting.
expect {
	var valid = Bool.True
	var number = -719528.I64
	var year = 0.I64
	while year < 400 {
		var month = 1.U8
		for common_length in [31.U8, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] {
			leap = I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0)
			length = if month == 2 and leap {
				29.U8
			} else {
				common_length
			}
			var day = 1.U8
			while day <= length {
				# Translate the enumerated cycle across year zero and near both
				# provider extremes using the independently counted cycle length.
				for offset in [-2147483600.I64, -400, 0, 2147483200] {
					fields = { year: year + offset, month, day }
					coordinate = CivilDay.from_day_number(
						number + I64.div_trunc_by(offset, 400) * 146097,
					)
					date = GregorianDate.from_fields(fields)
					valid = valid and GregorianDate.from_civil_day(coordinate) == date
					valid = valid and match date {
						Ok(value) => CivilDay.is_eq(GregorianDate.to_civil_day(value), coordinate)
						Err(_) => Bool.False
					}
				}
				number = number + 1
				day = day + 1
			}
			month = month + 1
		}
		year = year + 1
	}
	valid and number == -573431
}
