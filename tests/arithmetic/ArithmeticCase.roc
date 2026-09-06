import fuzz.Fuzz
import time.CalendarArithmetic
import time.CalendarDelta
import time.GregorianDate

# R05: field-walking oracle. It uses no production day conversion or month index.
Fields : { year : I64, month : U8, day : U8 }

ArithmeticCase := { year : I64, month : U8, day : U8, years : I64, months : I64, days : I64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(ArithmeticCase)
	generator_for = |_| {
		year: Fuzz.map2(
			Fuzz.u8_in(0, 4),
			Fuzz.u64_in(0, 4294967295),
			|choice, value| {
				match choice {
					0 => -2147483648.I64
					1 => 2147483647.I64
					2 => 0.I64
					_ => U64.to_i64_wrap(value) - 2147483648
				}
			},
		),
		month: Fuzz.u8_in(1, 12),
		day: Fuzz.u8_in(1, 31),
		years: Fuzz.map(Fuzz.u8_in(0, 4), |n| U8.to_i64(n) - 2),
		months: Fuzz.map(Fuzz.u8_in(0, 48), |n| U8.to_i64(n) - 24),
		days: Fuzz.map(Fuzz.u8_in(0, 120), |n| U8.to_i64(n) - 60),
	}.Fuzz

	check : ArithmeticCase -> Fuzz.Outcome
	check = |input| {
		length = month_length(input.year, input.month)
		fields = {
			year: input.year,
			month: input.month,
			day: if input.day < length {
				input.day
			} else {
				length
			},
		}
		date = match GregorianDate.from_fields(fields) {
			Ok(value) => value
			Err(_) => crash "arithmetic valid generator rejected"
		}
		for policy in [Reject, Clamp, Carry] {
			expected = model(fields, input.years, input.months, input.days, policy)
			actual = match CalendarArithmetic.shift_day(date, CalendarDelta.from_components({ years: input.years, months: input.months, days: input.days }), policy) {
				Ok(value) => Ok(GregorianDate.to_fields(value))
				Err(error) => Err(error)
			}
			if expected != actual {
				crash "R05 calendar arithmetic differs from field-walking oracle"
			}
		}
		# Deliberate full-width components must fail, never wrap into a valid year.
		if CalendarArithmetic.shift_day(date, CalendarDelta.months(I64.lowest), Carry) != Err(OutOfRange) or
			CalendarArithmetic.shift_day(date, CalendarDelta.years(I64.highest), Clamp) != Err(OutOfRange) or
				CalendarArithmetic.shift_day(date, CalendarDelta.days(I64.highest), Reject) != Err(OutOfRange) {
			crash "R05 unbounded component wrapped or accepted"
		}
		Fuzz.keep
	}
}

model : Fields, I64, I64, I64, CalendarArithmetic.Policy -> Try(Fields, [OutOfRange, InvalidDestination(Fields), ..])
model = |fields, years, months, days, policy| {
	after_years = repair({ year: fields.year + years, month: fields.month, day: fields.day }, policy)?
	var $next = after_years
	var $remaining = months
	# Move month labels first; do not repeatedly clamp intermediate dates.
	while $remaining != 0 {
		if $remaining > 0 {
			$next = if $next.month == 12 {
				{ year: $next.year + 1, month: 1, day: $next.day }
			} else {
				{ year: $next.year, month: $next.month + 1, day: $next.day }
			}
			$remaining = $remaining - 1
		} else {
			$next = if $next.month == 1 {
				{ year: $next.year - 1, month: 12, day: $next.day }
			} else {
				{ year: $next.year, month: $next.month - 1, day: $next.day }
			}
			$remaining = $remaining + 1
		}
	}
	walk(repair($next, policy)?, days)
}

repair : Fields, CalendarArithmetic.Policy -> Try(Fields, [OutOfRange, InvalidDestination(Fields), ..])
repair = |fields, policy| {
	if fields.year < -2147483648 or fields.year > 2147483647 {
		return Err(OutOfRange)
	}
	length = month_length(fields.year, fields.month)
	if fields.day <= length {
		return Ok(fields)
	}
	match policy {
		Reject => Err(InvalidDestination(fields))
		Clamp => Ok({ year: fields.year, month: fields.month, day: length })
		Carry => walk({ year: fields.year, month: fields.month, day: 1 }, U8.to_i64(fields.day) - 1)
	}
}

walk : Fields, I64 -> Try(Fields, [OutOfRange, ..])
walk = |fields, amount| {
	var $next = fields
	var $remaining = amount
	while $remaining != 0 {
		if $remaining > 0 {
			if $next.day < month_length($next.year, $next.month) {
				$next = { year: $next.year, month: $next.month, day: $next.day + 1 }
			} else if $next.month < 12 {
				$next = { year: $next.year, month: $next.month + 1, day: 1 }
			} else {
				$next = { year: $next.year + 1, month: 1, day: 1 }
			}
			$remaining = $remaining - 1
		} else {
			if $next.day > 1 {
				$next = { year: $next.year, month: $next.month, day: $next.day - 1 }
			} else {
				year = if $next.month == 1 {
					$next.year - 1
				} else {
					$next.year
				}
				month = if $next.month == 1 {
					12
				} else {
					$next.month - 1
				}
				$next = { year, month, day: month_length(year, month) }
			}
			$remaining = $remaining + 1
		}
		if $next.year < -2147483648 or $next.year > 2147483647 {
			return Err(OutOfRange)
		}
	}
	Ok($next)
}

month_length = |year, month| {
	base = match List.get([31.U8, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31], U8.to_u64(month - 1)) {
		Ok(value) => value
		Err(_) => crash "field model month precondition"
	}
	if month == 2 and I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0) {
		29
	} else {
		base
	}
}
