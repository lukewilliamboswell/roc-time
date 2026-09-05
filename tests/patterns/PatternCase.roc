import fuzz.Fuzz
import time.CalendarPattern
import time.GregorianDate

# R11 calendar candidates: field walking and a 400-year weekday counter oracle.
PatternCase := { year : I64, month : U8, interval : U8, index : U8, weekday : U8, ordinal : I8, month_day : I8 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(PatternCase)
	generator_for = |_| {
		year: Fuzz.map2(
			Fuzz.u8_in(0, 4),
			Fuzz.u64_in(0, 4294967295),
			|choice, n| match choice {
				0 => -2147483648.I64
				1 => 2147483647.I64
				2 => 0.I64
				_ => n.to_i64_wrap() - 2147483648
			},
		),
		month: Fuzz.u8_in(1, 12),
		interval: Fuzz.u8_in(1, 3),
		index: Fuzz.u8_in(0, 6),
		weekday: Fuzz.u8_in(0, 6),
		# Inputs are bounded below 127 before these exact narrowing operations.
		ordinal: Fuzz.map(Fuzz.u8_in(0, 10), |n| n.to_i8_wrap() - 5),
		month_day: Fuzz.map(Fuzz.u8_in(0, 62), |n| n.to_i8_wrap() - 31),
	}.Fuzz

	check : PatternCase -> Fuzz.Outcome
	check = |input| {
		anchor = date(input.year, input.month, 1)
		spec = { ..CalendarPattern.defaults(Monthly), interval: input.interval.to_i64(), by_month_day: [input.month_day], by_day: [{ ordinal: input.ordinal, weekday: weekday(input.weekday) }] }
		if input.month_day == 0 {
			match CalendarPattern.new(anchor, spec) {
				Err(InvalidSelector("BYMONTHDAY")) => return Fuzz.keep
				_ => crash "Zero month-day selector accepted"
			}
		}
		pattern = match CalendarPattern.new(anchor, spec) {
			Ok(value) => value
			Err(_) => crash "Valid pattern rejected"
		}
		var year = input.year
		var month = input.month
		var step = 0.U64
		while step < input.index.to_u64() * input.interval.to_u64() {
			if month == 12 {
				year = year + 1
				month = 1
			} else {
				month = month + 1
			}
			step = step + 1
		}
		var end_year = year
		var end_month = month + 1
		if end_month == 13 {
			end_year = end_year + 1
			end_month = 1
		}
		if end_year > 2147483647 {
			if CalendarPattern.period(pattern, input.index.to_u64()) != Err(OutOfRange) {
				crash "Period overflow concealed"
			}
			return Fuzz.keep
		}
		frame = match CalendarPattern.period(pattern, input.index.to_u64()) {
			Ok(value) => value
			Err(_) => crash "Supported period rejected"
		}
		if frame.start != date(year, month, 1) or frame.end != date(end_year, end_month, 1) {
			crash "Period differs from field walking"
		}
		length = month_length(year, month)
		var matching_days = []
		var day = 1.U8
		while day <= length {
			if weekday_oracle(year, month, day) == input.weekday.to_i64() {
				matching_days = matching_days.append(day)
			}
			day = day + 1
		}
		var selected_weekdays = []
		for (value, position) in matching_days.map_with_index(|value, position| (value, position)) {
			positive = position.to_i64_wrap() + 1
			negative = position.to_i64_wrap() - matching_days.len().to_i64_wrap()
			if input.ordinal == 0 or input.ordinal.to_i64() == positive or input.ordinal.to_i64() == negative {
				selected_weekdays = selected_weekdays.append(value)
			}
		}
		day = 1
		while day <= length {
			month_match = input.month_day.to_i64() == day.to_i64() or input.month_day.to_i64() == day.to_i64() - length.to_i64() - 1
			expected = month_match and selected_weekdays.contains(day)
			if CalendarPattern.matches(pattern, input.index.to_u64(), date(year, month, day)) != Ok(expected) {
				crash "Date selector differs from weekday enumeration"
			}
			day = day + 1
		}
		if CalendarPattern.matches(pattern, input.index.to_u64(), frame.end) != Ok(False) {
			crash "Exclusive period end included"
		}
		Fuzz.keep
	}
}

date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid generated date"
}

weekday = |value| match value {
	0 => Monday
	1 => Tuesday
	2 => Wednesday
	3 => Thursday
	4 => Friday
	5 => Saturday
	_ => Sunday
}

leap = |year| I64.mod_by(year, 4) == 0 and (I64.mod_by(year, 100) != 0 or I64.mod_by(year, 400) == 0)

month_length = |year, month| match month {
	2 => if leap(year) {
		29.U8
	} else {
		28
	}
	4 | 6 | 9 | 11 => 30
	_ => 31
}

weekday_oracle = |year, month, day| {
	# 2000-01-01 was Saturday. Walk at most one Gregorian 400-year cycle;
	# no production CivilDay conversion or floor-division year formula is used.
	end_year = 2000 + I64.mod_by(year, 400)
	var y = 2000.I64
	var elapsed = 0.I64
	while y < end_year {
		elapsed = elapsed + if leap(y) {
			366
		} else {
			365
		}
		y = y + 1
	}
	var m = 1.U8
	while m < month {
		elapsed = elapsed + month_length(end_year, m).to_i64()
		m = m + 1
	}
	I64.mod_by(5 + elapsed + day.to_i64() - 1, 7)
}
