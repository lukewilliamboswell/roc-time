import time.Calendar
import time.ClockTime
import time.GregorianDate
import time.LocalDateTime
import time.Recurrence.ClockPattern as ClockPattern
import time.Recurrence.SubdailyPattern as SubdailyPattern

ClockRanks := [].{}

day_us = 86400000000.I64

all_fields = |count| {
	var $fields = []
	var $value = 0.U8
	while $value < count {
		$fields = $fields.append($value)
		$value = $value + 1
	}
	$fields
}

# Enumerate the independent, ordered selector sets as tuples. No division
# or remainder by a selector length is needed to assign a rank.
grid = |selectors, fraction| {
	var $values = []
	for hour in selectors.hours {
		for minute in selectors.minutes {
			for second in selectors.seconds {
				micros = (hour.to_i64() * 3600 + minute.to_i64() * 60 + second.to_i64()) * 1000000 + fraction
				$values = $values.append(micros)
			}
		}
	}
	$values
}

# R05/R11. Exercise expanded dimensions of different sizes and inherit each
# field independently. Duplicates and source order cannot affect the ranks.
expect {
	anchor = ClockTime.from_fields({ hour: 17, minute: 43, second: 26, microsecond: 999999 })?
	hours = [23.U8, 3, 23, 0]
	minutes = [59.U8, 0, 59]
	seconds = [57.U8, 59, 1, 0, 57]
	ordered = { hours: [0.U8, 3, 23], minutes: [0.U8, 59], seconds: [0.U8, 1, 57, 59] }
	cases = [
		({ hours, minutes, seconds }, ordered),
		({ hours: [], minutes, seconds }, { ..ordered, hours: [17] }),
		({ hours, minutes: [], seconds }, { ..ordered, minutes: [43] }),
		({ hours, minutes, seconds: [] }, { ..ordered, seconds: [26] }),
	]
	var $valid = True
	for (requested, effective) in cases {
		pattern = ClockPattern.new(anchor, requested)?
		expected = grid(effective, 999999.I64)
		var $index = 0.U64
		for clock in ClockPattern.iter(pattern) {
			$valid = $valid and expected.get($index) == Ok(ClockTime.to_microseconds_since_midnight(clock)) and ClockPattern.at(pattern, $index) == Ok(clock)
			$index = $index + 1
		}
		$valid = $valid and $index == expected.len() and ClockPattern.count(pattern) == expected.len() and ClockPattern.at(pattern, $index) == Err(OutOfRange)
	}
	$valid
}

# The fully dense day makes each rank an independent integer second. Check
# both carry boundaries and the first indices that could alias valid ranks
# if a caller's U64 index were narrowed before validation.
expect {
	anchor = ClockTime.from_microseconds_since_midnight(999999)?
	parts = all_fields(60)
	pattern = ClockPattern.new(anchor, { hours: all_fields(24), minutes: parts, seconds: parts })?
	var $valid = ClockPattern.count(pattern) == 86400
	for index in [0.U64, 1, 59, 60, 3599, 3600, 86399] {
		$valid = $valid and ClockPattern.at(pattern, index).map_ok(ClockTime.to_microseconds_since_midnight) == Ok(index.to_i64_wrap() * 1000000 + 999999)
	}
	for index in [86400.U64, 86401, 4294967296, 4295053695, U64.highest] {
		$valid = $valid and ClockPattern.at(pattern, index) == Err(OutOfRange)
	}
	$valid
}

fixture_date = |day| {
	if day == -1 {
		GregorianDate.from_fields({ year: 1969, month: 12, day: 31 }) ?? crash "fixture date"
	} else {
		GregorianDate.from_fields({ year: 1970, month: 1, day: (day + 1).to_u8_wrap() }) ?? crash "fixture date"
	}
}

day_coordinate = |offset| {
	if offset < 0 {
		# All negative fixture offsets are in the one day before the epoch.
		return { day: -1.I64, time: offset + day_us }
	}
	var $day = 0.I64
	var $time = offset
	while $time >= day_us {
		$day = $day + 1
		$time = $time - day_us
	}
	{ day: $day, time: $time }
}

linear_rank = |coordinates, end| coordinates.fold(0.U64, |count, value| if (value < end) count + 1 else count)

# Subdaily periods select a half-open slice of the effective same-day grid.
# Use fixture epoch coordinates and linear rank counts as the oracle for
# both endpoints, including midnight and an exact zero-fraction boundary.
expect {
	calendar = { by_month: [], by_month_day: [], by_year_day: [], by_day: [] }
	hours = [23.U8, 3, 0, 23]
	minutes = [59.U8, 0, 59]
	seconds = [59.U8, 58, 0, 10, 58]
	cases = [
		(Hourly, { hours, minutes, seconds }, { hours: [0.U8, 3, 23], minutes: [0.U8, 59], seconds: [0.U8, 10, 58, 59] }, -3600000000.I64, 3600000000.I64),
		(Minutely, { hours: [], minutes, seconds: [] }, { hours: all_fields(24), minutes: [0.U8, 59], seconds: [58.U8] }, -60000000, 60000000),
		(Secondly, { hours, minutes: [], seconds }, { hours: [0.U8, 3, 23], minutes: all_fields(60), seconds: [0.U8, 10, 58, 59] }, -2000000, 1000000),
	]
	var $valid = True
	for fraction in [0.I64, 999999] {
		anchor = ClockTime.from_microseconds_since_midnight(day_us - 2000000 + fraction)?
		for (frequency, clocks, effective, start, unit) in cases {
			pattern = SubdailyPattern.new({ date: fixture_date(-1), clock: anchor }, { frequency, interval: 1, calendar, clocks })?
			coordinates = grid(effective, fraction)
			expected_fields = { hours: effective.hours, minutes: effective.minutes, seconds: effective.seconds, microsecond: fraction.to_u32_wrap() }
			$valid = $valid and ClockPattern.definition(SubdailyPattern.clocks(pattern)) == expected_fields
			for index in [0.U64, 1, 2, 3, 4, 25, 32, 59, 60, 61, 62] {
				a = start + index.to_i64_wrap() * unit
				from = day_coordinate(a)
				until = day_coordinate(a + unit)
				open_rank = linear_rank(coordinates, from.time)
				close_rank = if (from.day == until.day) linear_rank(coordinates, until.time) else coordinates.len()
				frame = SubdailyPattern.period(pattern, index)?
				$valid = $valid and frame.date == fixture_date(from.day) and frame.start_index == open_rank and frame.end_index == close_rank and
					LocalDateTime.date(frame.end) == Calendar.Date.from_gregorian(fixture_date(until.day)) and
						ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(frame.end)) == until.time
			}
		}
	}
	$valid
}
