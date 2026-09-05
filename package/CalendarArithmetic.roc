import CalendarDelta
import CivilDay
import GregorianDate

## Gregorian arithmetic. No timezone resolution or recurrence is implied.
CalendarArithmetic :: [].{
	Policy : [Reject, Clamp, Carry]

	shift_day : GregorianDate, CalendarDelta, Policy -> Try(GregorianDate, [OutOfRange, InvalidDestination(GregorianDate.Fields), ..])
	shift_day = |date, delta, policy| {
		parts = CalendarDelta.to_components(delta)
		fields = GregorianDate.to_fields(date)
		# Explicit mapping preserves the structured error contract on the pinned
		# interpreter; see tests/compiler_repro/result_widening/README.md.
		year = match narrow_year(I64.to_i128(fields.year) + I64.to_i128(parts.years)) {
			Ok(value) => value
			Err(OutOfRange) => return Err(OutOfRange)
		}
		after_years = destination(year, fields.month, fields.day, policy)?
		after_year_fields = GregorianDate.to_fields(after_years)
		# Gregorian alone has exactly twelve months per year. This is not a
		# generic calendar-provider equivalence between years and months.
		index = I64.to_i128(after_year_fields.year) * 12 + U8.to_i128(after_year_fields.month) - 1 + I64.to_i128(parts.months)
		month_year = match narrow_year(I128.div_floor_by(index, 12)) {
			Ok(value) => value
			Err(OutOfRange) => return Err(OutOfRange)
		}
		month = match I128.to_u8_try(I128.mod_by(index, 12) + 1) {
			Ok(value) => value
			Err(_) => crash "Gregorian month remainder invariant"
		}
		after_months = destination(month_year, month, after_year_fields.day, policy)?
		shift_days(after_months, parts.days)
	}

	expect {
		issued = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
		clamped = shift_day(issued, CalendarDelta.months(1), Clamp)?
		GregorianDate.to_fields(clamped) == { year: 2025, month: 2, day: 28 } and
			shift_day(issued, CalendarDelta.months(1), Reject) == Err(InvalidDestination({ year: 2025, month: 2, day: 31 })) and
				GregorianDate.to_fields(shift_day(issued, CalendarDelta.months(1), Carry)?) == { year: 2025, month: 3, day: 3 } and
					GregorianDate.to_fields(shift_day(clamped, CalendarDelta.months(-1), Clamp)?) == { year: 2025, month: 1, day: 28 }
	}

	expect {
		leap_day = GregorianDate.from_fields({ year: 2020, month: 2, day: 29 })?
		ordered = CalendarDelta.from_components({ years: 1, months: 1, days: 1 })
		GregorianDate.to_fields(shift_day(leap_day, ordered, Clamp)?) == { year: 2021, month: 3, day: 29 }
	}

	expect {
		january = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
		zero = GregorianDate.from_fields({ year: 0, month: 1, day: 31 })?
		# A two-month component has one destination; it does not clamp in February.
		GregorianDate.to_fields(shift_day(january, CalendarDelta.months(2), Clamp)?) == { year: 2025, month: 3, day: 31 } and
			GregorianDate.to_fields(shift_day(zero, CalendarDelta.months(-1), Reject)?) == { year: -1, month: 12, day: 31 }
	}

	expect {
		first = GregorianDate.from_fields({ year: -2147483648, month: 1, day: 1 })?
		last = GregorianDate.from_fields({ year: 2147483647, month: 12, day: 31 })?
		shift_day(first, CalendarDelta.days(-1), Clamp) == Err(OutOfRange) and
			shift_day(last, CalendarDelta.days(1), Clamp) == Err(OutOfRange) and
				shift_day(first, CalendarDelta.months(I64.lowest), Carry) == Err(OutOfRange) and
					shift_day(last, CalendarDelta.years(I64.highest), Reject) == Err(OutOfRange) and
						shift_day(last, CalendarDelta.from_components({ years: 1, months: -12, days: 0 }), Clamp) == Err(OutOfRange)
	}
}

narrow_year : I128 -> Try(I64, [OutOfRange, ..])
narrow_year = |year| {
	if year < -2147483648 or year > 2147483647 {
		return Err(OutOfRange)
	}
	I128.to_i64_try(year)
}

destination : I64, U8, U8, CalendarArithmetic.Policy -> Try(GregorianDate, [OutOfRange, InvalidDestination(GregorianDate.Fields), ..])
destination = |year, month, day, policy| {
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
		Err(_) => crash "Gregorian arithmetic destination invariant"
	}
	if day > length and policy == Carry {
		shift_days(valid, U8.to_i64(day - length))
	} else {
		Ok(valid)
	}
}

shift_days : GregorianDate, I64 -> Try(GregorianDate, [OutOfRange, ..])
shift_days = |date, days| {
	start = CivilDay.to_day_number(GregorianDate.to_civil_day(date))
	number = match I64.plus_try(start, days) {
		Ok(value) => value
		Err(Overflow) => return Err(OutOfRange)
	}
	GregorianDate.from_civil_day(CivilDay.from_day_number(number))
}
