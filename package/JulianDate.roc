import CivilDay

## Proleptic Julian day, with astronomical years (0 means 1 BCE).
## Valid years are -2147483648 through 2147483647, inclusive.
## No timezone or resolved timeline is implied by a date.
JulianDate :: [Date({ year : I64, month : U8, day : U8 })].{
	Fields : { year : I64, month : U8, day : U8 }

	from_fields : Fields -> Try(JulianDate, [OutOfRange, InvalidMonth, InvalidDay, ..])
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

	to_fields : JulianDate -> Fields
	to_fields = |Date(fields)| fields

	to_civil_day : JulianDate -> CivilDay
	to_civil_day = |Date(date)| {
		var before = 0.I64
		var month = 1.U8
		while month < date.month {
			before = before + U8.to_i64(month_length(date.year, month))
			month = month + 1
		}
		CivilDay.from_day_number(year_start(date.year) + before + U8.to_i64(date.day) - 1)
	}

	from_civil_day : CivilDay -> Try(JulianDate, [OutOfRange, ..])
	from_civil_day = |day| {
		number = CivilDay.to_day_number(day)
		if number < year_start(-2147483648) or number >= year_start(2147483648) {
			return Err(OutOfRange)
		}
		# Search a bounded provider range, not the distance from the epoch.
		var lower = -2147483648.I64
		var upper = 2147483648.I64
		while upper - lower > 1 {
			middle = lower + I64.div_trunc_by(upper - lower, 2)
			if year_start(middle) <= number {
				lower = middle
			} else {
				upper = middle
			}
		}
		var remaining = number - year_start(lower)
		var month = 1.U8
		while remaining >= U8.to_i64(month_length(lower, month)) {
			remaining = remaining - U8.to_i64(month_length(lower, month))
			month = month + 1
		}
		# The selected year contains number; remaining is in 0..30, month in 1..12.
		day_of_month = match I64.to_u8_try(remaining + 1) {
			Ok(value) => value
			Err(_) => crash "Julian decomposition invariant"
		}
		Ok(Date({ year: lower, month, day: day_of_month }))
	}

	to_hash : JulianDate, Hasher -> Hasher
	to_hash = |Date(fields), hasher| fields.day.to_hash(fields.month.to_hash(fields.year.to_hash(hasher)))

	to_inspect : JulianDate -> Str
	to_inspect = |Date(fields)| "JulianDate(${fields.year.to_str()}, ${fields.month.to_str()}, ${fields.day.to_str()})"

	is_lt : JulianDate, JulianDate -> Bool
	is_lt = |a, b| to_civil_day(a) < to_civil_day(b)

	is_lte : JulianDate, JulianDate -> Bool
	is_lte = |a, b| to_civil_day(a) <= to_civil_day(b)

	is_gt : JulianDate, JulianDate -> Bool
	is_gt = |a, b| to_civil_day(a) > to_civil_day(b)

	is_gte : JulianDate, JulianDate -> Bool
	is_gte = |a, b| to_civil_day(a) >= to_civil_day(b)

	is_eq : JulianDate, JulianDate -> Bool
	is_eq = |Date(a), Date(b)| a.year == b.year and a.month == b.month and a.day == b.day

	expect {
		fields = { year: 1900, month: 2, day: 29 }
		date = from_fields(fields)?
		to_fields(date) == fields
	}
	expect from_fields({ year: 1901, month: 2, day: 29 }) == Err(InvalidDay)
	expect from_civil_day(CivilDay.from_day_number(-784369121963)) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(784367682902)) == Err(OutOfRange)
	expect {
		date = from_fields({ year: 1969, month: 12, day: 19 })?
		CivilDay.to_day_number(to_civil_day(date)) == 0 and from_civil_day(CivilDay.from_day_number(0)) == Ok(date)
	}

}

# Counts complete years before January 1 relative to Gregorian 1970-01-01.
# All callers constrain year to [-2147483648, 2147483648]; intermediates fit I64.
# Floor division, including before year zero, counts Julian leap years.
year_start : I64 -> I64
year_start = |year| {
	previous = year - 1
	365 * previous + I64.div_floor_by(previous, 4) - 719164
}

# Internal callers establish a valid year and month in 1..12.
month_length : I64, U8 -> U8
month_length = |year, month| {
	match month {
		2 => if I64.rem_by(year, 4) == 0 {
			29
		} else {
			28
		}
		4 | 6 | 9 | 11 => 30
		_ => 31
	}
}
