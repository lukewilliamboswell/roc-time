import TimedRecurrence
import CalendarPattern
import Calendar
import PosixBoundary
import LocalDateTime
import PersistenceLocal

## Internal native recurrence block in a flat JSON string array. No RRULE
## lowering, zone resolution or occurrence expansion. Exact prefix indices:
## 0 anchor; 1 calendar/subdaily; 2 frequency; 3 interval; 4 week start;
## 5 BYMONTH; 6 BYWEEKNO; 7 BYYEARDAY; 8 BYMONTHDAY; 9 BYDAY;
## 10 hours; 11 minutes; 12 seconds; 13 BYSETPOS;
## 14 forever/count/until-local/until-boundary; 15 termination argument;
## 16 inclusion count, then local labels, exclusion count and local labels.
## Native fraction-6 local fields preserve calendar identity and microseconds.
## Selector fields are empty or comma-separated canonical integers; BYDAY uses
## mo:0,tu:-1 pairs. List order/duplicates survive wherever native constructors
## preserve them. Subdaily week start/BYWEEKNO must be empty and ordinals zero.
## COUNT accepts the full U64 range; other numeric domains remain checked.
## At most 4096 combined selectors and 1024 combined exceptions. The containing
## archive enforces 49152 payload/65536 envelope bytes. Individual block fields
## are also bounded to 49152 bytes before scanning; suffix fields are untouched.
## from_fields returns the exact consumed prefix and remaining schedule fields.
PersistenceRecurrence := [].{
	NativeError : [UnsupportedCalendar(Calendar), InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart]
	Error : [TooLarge, TooManySelectors, TooManyExceptions, Incomplete, Malformed, InvalidInteger, OutOfRange, UnsupportedPattern(Str), UnsupportedFrequency(Str), InvalidLocal(PersistenceLocal.Error), InvalidRecurrence(NativeError)]
	fits : TimedRecurrence -> Bool
	fits = |rule| {
		data = TimedRecurrence.definition(rule)
		selector_count(data) <= 4096 and data.inclusions.len() <= 1024 and data.exclusions.len() <= 1024 - data.inclusions.len()
	}
	to_fields : TimedRecurrence -> Try(List(Str), Error)
	to_fields = |rule| {
		data = TimedRecurrence.definition(rule)
		if selector_count(data) > 4096 {
			return Err(TooManySelectors)
		}
		if data.inclusions.len() > 1024 or data.exclusions.len() > 1024 - data.inclusions.len() {
			return Err(TooManyExceptions)
		}
		(kind, frequency, interval, week, months, weeks, years, days, weekdays) = match data.pattern {
			Calendar(p) => ("calendar", calendar_frequency(p.frequency), p.interval, weekday(p.week_start), p.by_month, p.by_week_no, p.by_year_day, p.by_month_day, p.by_day)
			Subdaily(p) => (
				"subdaily",
				match p.frequency {
					Hourly => "hourly"
					Minutely => "minutely"
					Secondly => "secondly"
				},
				p.interval,
				"",
				p.calendar.by_month,
				[],
				p.calendar.by_year_day,
				p.calendar.by_month_day,
				p.calendar.by_day.map(|day| { weekday: day, ordinal: 0 }),
			)
		}
		(termination, argument) = match data.termination {
			Forever => ("forever", "")
			Count(n) => ("count", n.to_str())
			Until(label) => ("until-local", PersistenceLocal.to_text(label))
			UntilBoundary(point) => ("until-boundary", PosixBoundary.to_microseconds(point).to_str())
		}
		fields = [PersistenceLocal.to_text(data.anchor), kind, frequency, interval.to_str(), week, numbers_text(months.map(|n| n.to_i64())), numbers_text(weeks.map(|n| n.to_i64())), numbers_text(years.map(|n| n.to_i64())), numbers_text(days.map(|n| n.to_i64())), Str.join_with(weekdays.map(|day| "${weekday(day.weekday)}:${day.ordinal.to_str()}"), ","), numbers_text(data.clocks.hours.map(|n| n.to_i64())), numbers_text(data.clocks.minutes.map(|n| n.to_i64())), numbers_text(data.clocks.seconds.map(|n| n.to_i64())), numbers_text(data.by_set_pos.map(|n| n.to_i64())), termination, argument, data.inclusions.len().to_str()]
		Ok(fields.concat(data.inclusions.map(PersistenceLocal.to_text)).append(data.exclusions.len().to_str()).concat(data.exclusions.map(PersistenceLocal.to_text)))
	}
	from_fields : List(Str) -> Try({ value : TimedRecurrence, rest : List(Str), consumed : U64 }, Error)
	from_fields = |fields| {
		if fields.len() < 17 {
			return Err(Incomplete)
		}
		for field in fields.take_first(17) {
			if field.count_utf8_bytes() > 49152 {
				return Err(TooLarge)
			}
		}
		var $selectors = 0.U64
		for index in [5.U64, 6, 7, 8, 9, 10, 11, 12, 13] {
			$selectors = $selectors + list_count(at(fields, index))
			if $selectors > 4096 {
				return Err(TooManySelectors)
			}
		}
		included = unsigned(at(fields, 16))?
		if included > 1024 {
			return Err(TooManyExceptions)
		}
		exclusion_index = 17 + included
		if fields.len() <= exclusion_index {
			return Err(Incomplete)
		}
		if at(fields, exclusion_index).count_utf8_bytes() > 49152 {
			return Err(TooLarge)
		}
		excluded = unsigned(at(fields, exclusion_index))?
		if excluded > 1024 - included {
			return Err(TooManyExceptions)
		}
		consumed = exclusion_index + 1 + excluded
		if fields.len() < consumed {
			return Err(Incomplete)
		}
		anchor = local(at(fields, 0))?
		interval = integer(at(fields, 3))?
		months = numbers(at(fields, 5), 0, 255)?.map(|n| n.to_u8_wrap())
		weeks = numbers(at(fields, 6), -128, 127)?.map(|n| n.to_i8_wrap())
		years = numbers(at(fields, 7), -32768, 32767)?.map(|n| n.to_i16_wrap())
		days = numbers(at(fields, 8), -128, 127)?.map(|n| n.to_i8_wrap())
		weekdays = day_list(at(fields, 9))?
		pattern = match at(fields, 1) {
			"calendar" => Calendar({ frequency: parse_calendar_frequency(at(fields, 2))?, interval, week_start: parse_weekday(at(fields, 4))?, by_month: months, by_week_no: weeks, by_year_day: years, by_month_day: days, by_day: weekdays })
			"subdaily" => {
				if at(fields, 4) != "" or !weeks.is_empty() or !weekdays.all(|day| day.ordinal == 0) {
					return Err(Malformed)
				}
				frequency = match at(fields, 2) {
					"hourly" => Hourly
					"minutely" => Minutely
					"secondly" => Secondly
					other => return Err(UnsupportedFrequency(other))
				}
				Subdaily({ frequency, interval, calendar: { by_month: months, by_year_day: years, by_month_day: days, by_day: weekdays.map(|day| day.weekday) } })
			}
			other => return Err(UnsupportedPattern(other))
		}
		clocks = { hours: numbers(at(fields, 10), 0, 255)?.map(|n| n.to_u8_wrap()), minutes: numbers(at(fields, 11), 0, 255)?.map(|n| n.to_u8_wrap()), seconds: numbers(at(fields, 12), 0, 255)?.map(|n| n.to_u8_wrap()) }
		by_set_pos = numbers(at(fields, 13), -32768, 32767)?.map(|n| n.to_i16_wrap())
		termination = match at(fields, 14) {
			"forever" => {
				if at(fields, 15) != "" {
					return Err(Malformed)
				}
				Forever
			}
			"count" => Count(unsigned(at(fields, 15))?)
			"until-local" => Until(local(at(fields, 15))?)
			"until-boundary" => UntilBoundary(PosixBoundary.from_microseconds(integer(at(fields, 15))?))
			_ => return Err(Malformed)
		}
		var $inclusions = []
		for text in fields.sublist({ start: 17, len: included }) {
			$inclusions = $inclusions.append(local(text)?)
		}
		var $exclusions = []
		for text in fields.sublist({ start: exclusion_index + 1, len: excluded }) {
			$exclusions = $exclusions.append(local(text)?)
		}
		value = match TimedRecurrence.from_definition({ anchor, pattern, clocks, termination, by_set_pos, inclusions: $inclusions, exclusions: $exclusions }) {
			Ok(rule) => rule
			Err(error) => return Err(InvalidRecurrence(error))
		}
		Ok({ value, consumed, rest: fields.drop_first(consumed) })
	}
}

selector_count = |data| {
	calendar_count = match data.pattern {
		Calendar(p) => p.by_month.len() + p.by_week_no.len() + p.by_year_day.len() + p.by_month_day.len() + p.by_day.len()
		Subdaily(p) => p.calendar.by_month.len() + p.calendar.by_year_day.len() + p.calendar.by_month_day.len() + p.calendar.by_day.len()
	}
	calendar_count + data.clocks.hours.len() + data.clocks.minutes.len() + data.clocks.seconds.len() + data.by_set_pos.len()
}

numbers_text = |values| Str.join_with(values.map(|n| n.to_str()), ",")

list_count = |text| {
	if text.is_empty() {
		return 0.U64
	}
	var $count = 1.U64
	for byte in text.to_utf8() {
		if byte == 44 {
			$count = $count + 1
		}
	}
	$count
}

at = |fields, index| fields.get(index) ?? crash "Validated recurrence field index"

local = |text| match PersistenceLocal.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(InvalidLocal(error))
}

integer = |text| {
	canonical_digits(text, Bool.True)?
	match I64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

unsigned = |text| {
	canonical_digits(text, Bool.False)?
	match U64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

canonical_digits = |text, signed| {
	bytes = text.to_utf8()
	if bytes.is_empty() {
		return Err(InvalidInteger)
	}
	negative = signed and bytes.first() == Ok(45)
	digits = if negative {
		bytes.drop_first(1)
	} else {
		bytes
	}
	if digits.is_empty() or !digits.all(|byte| byte >= 48 and byte <= 57) {
		return Err(InvalidInteger)
	}
	if digits.first() == Ok(48) and (digits.len() > 1 or negative) {
		return Err(InvalidInteger)
	}
	Ok({})
}

numbers = |text, minimum, maximum| {
	var $values = []
	if text.is_empty() {
		return Ok($values)
	}
	for token in text.split_on(",") {
		value = integer(token)?
		if value < minimum or value > maximum {
			return Err(OutOfRange)
		}
		$values = $values.append(value)
	}
	Ok($values)
}

day_list = |text| {
	var $days = []
	if text.is_empty() {
		return Ok($days)
	}
	for token in text.split_on(",") {
		pair = token.split_on(":")
		if pair.len() != 2 {
			return Err(Malformed)
		}
		day = parse_weekday(at(pair, 0))?
		ordinal = integer(at(pair, 1))?
		if ordinal < -128 or ordinal > 127 {
			return Err(OutOfRange)
		}
		$days = $days.append({ weekday: day, ordinal: ordinal.to_i8_wrap() })
	}
	Ok($days)
}

weekday = |day| match day {
	Monday => "mo"
	Tuesday => "tu"
	Wednesday => "we"
	Thursday => "th"
	Friday => "fr"
	Saturday => "sa"
	Sunday => "su"
}

parse_weekday = |text| match text {
	"mo" => Ok(Monday)
	"tu" => Ok(Tuesday)
	"we" => Ok(Wednesday)
	"th" => Ok(Thursday)
	"fr" => Ok(Friday)
	"sa" => Ok(Saturday)
	"su" => Ok(Sunday)
	_ => Err(Malformed)
}

calendar_frequency = |frequency| match frequency {
	Daily => "daily"
	Weekly => "weekly"
	Monthly => "monthly"
	Yearly => "yearly"
}

parse_calendar_frequency = |text| match text {
	"daily" => Ok(Daily)
	"weekly" => Ok(Weekly)
	"monthly" => Ok(Monthly)
	"yearly" => Ok(Yearly)
	other => Err(UnsupportedFrequency(other))
}

# R01/R11/R14: hand-authored native fields preserve U64 COUNT above I64,
# the epoch's first microsecond and a distinct Julian exclusion description.
# Calendar/clock fields are checked directly, not inferred from rendered text.
expect {
	fields = test_fields("count", "18446744073709551615")
	decoded = PersistenceRecurrence.from_fields(fields.concat(["duration-suffix"]))?
	data = TimedRecurrence.definition(decoded.value)
	data.termination == Count(U64.highest) and decoded.consumed == 19 and decoded.rest == ["duration-suffix"] and
		PersistenceLocal.to_text(data.anchor) == "gregorian;fraction;1970;1;1;0;0;0;6;1" and
			data.exclusions.map(PersistenceLocal.to_text) == ["julian;fraction;1969;12;19;0;0;0;6;1"] and
				PersistenceRecurrence.to_fields(decoded.value)? == fields
}

expect {
	var $valid = Bool.True
	for text in ["", "+1", "01", "-0", "-1", " 1", "1 ", "1.0"] {
		$valid = $valid and test_status(test_fields("count", text)) == Err(InvalidInteger)
	}
	$valid and test_status(test_fields("count", "18446744073709551616")) == Err(OutOfRange) and
		test_status(test_fields("count", "0")) == Err(InvalidRecurrence(InvalidCount)) and
			test_status(test_fields("forever", "1")) == Err(Malformed)
}

# Signed coordinate endpoints remain independent from local termination labels.
expect {
	minimum = PersistenceRecurrence.from_fields(test_fields("until-boundary", "-9223372036854775808"))?
	maximum = PersistenceRecurrence.from_fields(test_fields("until-boundary", "9223372036854775807"))?
	TimedRecurrence.definition(minimum.value).termination == UntilBoundary(PosixBoundary.from_microseconds(I64.lowest)) and
		TimedRecurrence.definition(maximum.value).termination == UntilBoundary(PosixBoundary.from_microseconds(I64.highest)) and
			test_status(test_fields("until-boundary", "-9223372036854775809")) == Err(OutOfRange) and
				test_status(test_fields("until-boundary", "-0")) == Err(InvalidInteger)
}

# Native calendars retain selector order and duplicate predicates; clock
# selectors normalize through the established checked ClockPattern constructor.
expect {
	fields = ["gregorian;fraction;1970;1;1;0;0;0;6;999999", "subdaily", "hourly", "2", "", "12,1,12", "", "", "", "th:0,th:0", "1,0,1", "0", "0,30", "", "count", "2", "0", "0"]
	decoded = PersistenceRecurrence.from_fields(fields)?
	data = TimedRecurrence.definition(decoded.value)
	parsed = match data.pattern {
		Subdaily(p) => p.frequency == Hourly and p.interval == 2 and p.calendar.by_month == [12, 1, 12] and p.calendar.by_day == [Thursday, Thursday]
		Calendar(_) => Bool.False
	}
	parsed and data.clocks == { hours: [0, 1], minutes: [0], seconds: [0, 30] } and
		PersistenceLocal.to_text(data.anchor) == "gregorian;fraction;1970;1;1;0;0;0;6;999999"
}

# Count limits precede malformed content and missing variable-field decoding.
expect {
	base = test_fields("forever", "")
	too_many_selectors = base.take_first(5).append(Str.repeat("1,", 4096)).concat(base.drop_first(6))
	too_many_exceptions = base.take_first(16).append("1025")
	test_status(too_many_selectors) == Err(TooManySelectors) and
		test_status(too_many_exceptions) == Err(TooManyExceptions) and
			test_status(base.take_first(17)) == Err(Incomplete) and
				test_status(base.take_first(16).concat(["0", "1025"])) == Err(TooManyExceptions)
}

# Three effective clock selectors leave exactly 4093 calendar selector entries
# in the archive budget. Duplicate predicates are retained, not discounted.
expect {
	base = test_fields("forever", "")
	months = Str.repeat("1,", 4092).concat("1")
	fields = base.take_first(5).append(months).concat(base.drop_first(6))
	decoded = PersistenceRecurrence.from_fields(fields)?
	PersistenceRecurrence.fits(decoded.value) and PersistenceRecurrence.to_fields(decoded.value)? == fields and
		test_status(base.take_first(5).append(months.concat(",1")).concat(base.drop_first(6))) == Err(TooManySelectors)
}

test_fields = |termination, argument| ["gregorian;fraction;1970;1;1;0;0;0;6;1", "calendar", "daily", "1", "mo", "", "", "", "", "", "0", "0", "0", "", termination, argument, "0", "1", "julian;fraction;1969;12;19;0;0;0;6;1"]

test_status = |fields| match PersistenceRecurrence.from_fields(fields) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
