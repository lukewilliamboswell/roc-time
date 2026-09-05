import CivilDay

## Proleptic Gregorian day, with astronomical years (0 means 1 BCE).
## Valid years are -2147483648 through 2147483647, inclusive.
## No timezone or resolved timeline is implied by a date.
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
		var before = 0.I64
		var month = 1.U8
		while month < date.month {
			before = before + U8.to_i64(month_length(date.year, month))
			month = month + 1
		}
		CivilDay.from_day_number(year_start(date.year) + before + U8.to_i64(date.day) - 1)
	}

	from_civil_day : CivilDay -> Try(GregorianDate, [OutOfRange, ..])
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
			Err(_) => crash "Gregorian decomposition invariant"
		}
		Ok(Date({ year: lower, month, day: day_of_month }))
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
				# Translate each enumerated day to the previous cycle as well;
				# this crosses year zero without using a floor-division oracle.
				for offset in [-400.I64, 0] {
					fields = { year: year + offset, month, day }
					coordinate = CivilDay.from_day_number(
						number + if offset == 0 {
							0
						} else {
							-146097
						},
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
