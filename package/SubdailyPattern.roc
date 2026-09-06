import CalendarPattern
import CalendarDate
import GregorianDate
import CivilDay
import ClockTime
import ClockPattern
import LocalDateTime

## Anchored local clock periods. Higher fields restrict the moving period;
## lower fields expand it, inheriting omitted values from the original clock.
## Period arithmetic uses nominal civil seconds, never resolved elapsed time.
SubdailyPattern :: { anchor_second : I128, unit : I128, interval : I128, clocks : ClockPattern, dates : CalendarPattern.Filter }.{
	Frequency : [Hourly, Minutely, Secondly]
	Spec : { frequency : Frequency, interval : I64, calendar : CalendarPattern.Filter.Spec, clocks : ClockPattern.Spec }
	Period : { date : GregorianDate, start_index : U64, end_index : U64, end : LocalDateTime }
	new : { date : GregorianDate, clock : ClockTime }, Spec -> Try(SubdailyPattern, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, ..])
	new = |start, spec| {
		if spec.interval < 1 or spec.interval > 2147483647 {
			return Err(InvalidInterval)
		}
		unit = match spec.frequency {
			Hourly => 3600.I128
			Minutely => 60.I128
			Secondly => 1.I128
		}
		seconds = I64.div_trunc_by(ClockTime.to_microseconds_since_midnight(start.clock), 1000000).to_i128()
		anchor_second = CivilDay.to_day_number(GregorianDate.to_civil_day(start.date)).to_i128() * 86400 + I128.div_trunc_by(seconds, unit) * unit
		# An omitted limiting field is unrestricted, unlike an omitted
		# expanding field, whose original anchor value is inherited.
		hours = if spec.clocks.hours.is_empty() {
			all_fields(24)
		} else {
			spec.clocks.hours
		}
		minutes = if spec.frequency != Hourly and spec.clocks.minutes.is_empty() {
			all_fields(60)
		} else {
			spec.clocks.minutes
		}
		seconds_list = if spec.frequency == Secondly and spec.clocks.seconds.is_empty() {
			all_fields(60)
		} else {
			spec.clocks.seconds
		}
		clocks = ClockPattern.new(start.clock, { hours, minutes, seconds: seconds_list })?
		dates = CalendarPattern.Filter.new(spec.calendar)?
		Ok({ anchor_second, unit, interval: spec.interval.to_i128(), clocks, dates })
	}

	## Effective declaration parameters. Construction proves interval fits I64.
	## calendar carries filter predicates only; its period fields are placeholders.
	definition : SubdailyPattern -> { frequency : Frequency, interval : I64, calendar : CalendarPattern.Spec }
	definition = |pattern| {
		frequency = match pattern.unit {
			3600 => Hourly
			60 => Minutely
			_ => Secondly
		}
		{ frequency, interval: pattern.interval.to_i64_wrap(), calendar: CalendarPattern.Filter.definition(pattern.dates) }
	}
	clocks : SubdailyPattern -> ClockPattern
	clocks = |pattern| pattern.clocks
	matches_date : SubdailyPattern, GregorianDate -> Try(Bool, [OutOfRange, ..])
	matches_date = |pattern, date| CalendarPattern.Filter.matches(pattern.dates, date)

	## Constant arithmetic plus O(log 86400) clock seeks; no intervening
	## periods are visited. Both boundaries must fit the Gregorian provider.
	period : SubdailyPattern, U64 -> Try(Period, [OutOfRange, ..])
	period = |pattern, index| {
		start = pattern.anchor_second + index.to_i128() * pattern.interval * pattern.unit
		end_second = start + pattern.unit
		day_number = I128.div_floor_by(start, 86400)
		date = date_at(day_number)?
		end_day = I128.div_floor_by(end_second, 86400)
		end_date = date_at(end_day)?
		start_microsecond = narrow(I128.mod_by(start, 86400) * 1000000)?
		end_microsecond = if end_day == day_number {
			narrow(I128.mod_by(end_second, 86400) * 1000000)?
		} else {
			86400000000.I64
		}
		end_clock = match ClockTime.from_microseconds_since_midnight(narrow(I128.mod_by(end_second, 86400) * 1000000)?) {
			Ok(value) => value
			Err(_) => crash "subdaily clock remainder"
		}
		Ok({ date, start_index: lower_bound(pattern.clocks, start_microsecond), end_index: lower_bound(pattern.clocks, end_microsecond), end: LocalDateTime.new(CalendarDate.from_gregorian(end_date), end_clock) })
	}

	## Compare the next whole-period start without requiring that far-future
	## date to fit the provider. A finite query can finish before a huge step.
	starts_before : SubdailyPattern, U64, LocalDateTime -> Bool
	starts_before = |pattern, index, boundary| {
		start = pattern.anchor_second + index.to_i128() * pattern.interval * pattern.unit
		micros = ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(boundary))
		second = CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(boundary))).to_i128() * 86400 + I64.div_trunc_by(micros, 1000000).to_i128()
		start < second or (start == second and I64.rem_by(micros, 1000000) > 0)
	}

	to_inspect : SubdailyPattern -> Str
	to_inspect = |pattern| "SubdailyPattern(unit_seconds=${pattern.unit.to_str()}, interval=${pattern.interval.to_str()})"
}

all_fields = |count| {
	var result = []
	var value = 0.U8
	while value < count {
		result = result.append(value)
		value = value + 1
	}
	result
}

narrow = |value| I128.to_i64_try(value)

date_at = |number| {
	day = narrow(number)?
	GregorianDate.from_civil_day(CivilDay.from_day_number(day))
}

lower_bound = |pattern, microsecond| {
	var lower = 0.U64
	var upper = ClockPattern.count(pattern)
	while lower < upper {
		middle = lower + U64.div_trunc_by(upper - lower, 2)
		clock = match ClockPattern.at(pattern, middle) {
			Ok(value) => value
			Err(_) => crash "clock seek invariant"
		}
		if ClockTime.to_microseconds_since_midnight(clock) < microsecond {
			lower = middle + 1
		} else {
			upper = middle
		}
	}
	lower
}

expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields({ hour: 9, minute: 30, second: 0, microsecond: 1 })?
	pattern = SubdailyPattern.new(
		{ date, clock },
		{
			frequency: Hourly,
			interval: 1,
			calendar: { by_month: [], by_month_day: [], by_year_day: [], by_day: [] },
			clocks: { hours: [9], minutes: [0, 30], seconds: [] },
		},
	)?
	first = SubdailyPattern.period(pattern, 0)?
	filtered = SubdailyPattern.period(pattern, 1)?
	first.start_index == 0 and first.end_index == 2 and filtered.start_index == filtered.end_index
}

expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	pattern = SubdailyPattern.new(
		{ date, clock },
		{
			frequency: Hourly,
			interval: 2147483647,
			calendar: { by_month: [], by_month_day: [], by_year_day: [], by_day: [] },
			clocks: { hours: [], minutes: [], seconds: [] },
		},
	)?
	match SubdailyPattern.period(pattern, U64.highest) {
		Err(OutOfRange) => Bool.True
		_ => Bool.False
	}
}

expect {
	date = GregorianDate.from_fields({ year: 2147483647, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	pattern = SubdailyPattern.new({ date, clock }, { frequency: Hourly, interval: 2147483647, calendar: { by_month: [], by_month_day: [], by_year_day: [], by_day: [] }, clocks: { hours: [], minutes: [], seconds: [] } })?
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 2147483647, month: 1, day: 2 })?), clock)
	!SubdailyPattern.starts_before(pattern, 1, end) and match SubdailyPattern.period(pattern, 1) {
		Err(OutOfRange) => Bool.True
		_ => Bool.False
	}
}
