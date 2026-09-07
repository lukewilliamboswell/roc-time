import Calendar
import CivilDay
import ClockTime
import GregorianDate

## A dated local label. A zone occurrence has not been selected or resolved.
##
## Example
##
## Combine a calendar date with a wall-clock label before choosing a timezone.
## Construction alone does not resolve daylight-saving gaps or folds.
##
## ```roc
## import time.GregorianDate
## import time.Calendar.Date
## import time.ClockTime
## import time.LocalDateTime
##
## expect {
##     date = GregorianDate.from_fields({ year: 2025, month: 6, day: 12 })?
##     clock = ClockTime.from_fields({
##         hour: 9,
##         minute: 30,
##         second: 0,
##         microsecond: 0,
##     })?
##     local = LocalDateTime.new(Calendar.Date.from_gregorian(date), clock)
##     ClockTime.to_fields(LocalDateTime.clock(local)).hour == 9
## }
## ```
##
## An explicitly Gregorian form field can also be read directly. A local label
## still needs separately supplied rules and an occurrence policy to resolve it.
## This text profile rejects offsets and preserves microseconds, but does not
## retain supplied-field resolution or serialize non-Gregorian calendars.
##
## ```roc
## import time.LocalDateTime
##
## expect {
##     appointment = LocalDateTime.parse_gregorian("2026-09-07T09:30")?
##     LocalDateTime.to_gregorian_text(appointment) == Ok("2026-09-07T09:30:00")
## }
## ```
##
## Examples assume a package dependency named `time`.
LocalDateTime :: { date : Calendar.Date, clock : ClockTime }.{

	## Canonical start of a civil selection, without changing its supplied precision.
	## This label alone does not describe the selection's extent or choose a zone.
	from_calendar_value : Calendar.Value -> LocalDateTime
	from_calendar_value = |value| new(Calendar.Value.date(value), Calendar.Value.clock(value))

	## Compose checked half-open civil bounds from selection components in O(1).
	## An exclusive upper bound beyond the provider range returns OutOfRange.
	calendar_value_bounds : Calendar.Value -> Try({ start : LocalDateTime, end : LocalDateTime }, [OutOfRange, ..])
	calendar_value_bounds = |value| {
		bounds = Calendar.Value.bounds(value)?
		Ok({ start: new(bounds.start.date, bounds.start.clock), end: new(bounds.end.date, bounds.end.clock) })
	}

	TextError : [TooLarge, Incomplete, Malformed, InvalidDate(GregorianDate.Error), InvalidTime(ClockTime.Error)]

	## Parse an explicitly Gregorian local label: date, uppercase T, then clock.
	## The date and clock use GregorianDate.parse and ClockTime.parse profiles.
	## At most 64 UTF-8 bytes; omitted clock seconds become zero. No offset,
	## zone, occurrence or supplied-field resolution is inferred. This native
	## profile does not claim all ISO 8601 forms. Julian values require explicit
	## construction; their fields are never silently treated as Gregorian.
	parse_gregorian : Str -> Try(LocalDateTime, TextError)
	parse_gregorian = |text| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		(date_text, clock_text) = match text.split_on("T") {
			[a, b] => (a, b)
			[a] => {
				return match GregorianDate.parse(a) {
					Ok(_) => Err(Incomplete)
					Err(Incomplete) => Err(Incomplete)
					Err(error) => Err(InvalidDate(error))
				}
			}
			_ => return Err(Malformed)
		}
		day = match GregorianDate.parse(date_text) {
			Ok(value) => value
			# A separator after a partial date cannot become valid by appending.
			Err(Incomplete) => return Err(InvalidDate(Malformed))
			Err(error) => return Err(InvalidDate(error))
		}
		time = match ClockTime.parse(clock_text) {
			Ok(value) => value
			Err(Incomplete) => return Err(Incomplete)
			Err(error) => return Err(InvalidTime(error))
		}
		Ok(new(Calendar.Date.from_gregorian(day), time))
	}

	## Canonical Gregorian date/clock text preserves the local position. It is
	## neither a resolved timestamp nor a persistence format for every calendar.
	## Reject other calendars; callers can explicitly convert with in_calendar.
	to_gregorian_text : LocalDateTime -> Try(Str, [UnsupportedCalendar(Calendar), ..])
	to_gregorian_text = |value| {
		day = Calendar.Date.as_gregorian(value.date)?
		Ok("${GregorianDate.to_text(day)}T${ClockTime.to_text(value.clock)}")
	}

	new : Calendar.Date, ClockTime -> LocalDateTime
	new = |date, clock| { date, clock }

	date : LocalDateTime -> Calendar.Date
	date = |value| value.date
	clock : LocalDateTime -> ClockTime
	clock = |value| value.clock

	in_calendar : LocalDateTime, Calendar -> Try(LocalDateTime, [OutOfRange, ..])
	in_calendar = |value, target| {
		converted = Calendar.Date.in_calendar(value.date, target)?
		Ok(new(converted, value.clock))
	}

	## Compare local positions, not timeline occurrences or descriptions.
	compare_position : LocalDateTime, LocalDateTime -> [LT, EQ, GT]
	compare_position = |a, b| {
		days = CivilDay.compare(Calendar.Date.to_civil_day(a.date), Calendar.Date.to_civil_day(b.date))
		match days {
			EQ => if a.clock < b.clock {
				LT
			} else if a.clock > b.clock {
				GT
			} else {
				EQ
			}
			other => other
		}
	}

	same_position : LocalDateTime, LocalDateTime -> Bool
	same_position = |a, b| compare_position(a, b) == EQ

	## Description equality preserves the calendar as well as the clock label.
	is_eq : LocalDateTime, LocalDateTime -> Bool
	is_eq = |a, b| a.date == b.date and a.clock == b.clock
	to_hash : LocalDateTime, Hasher -> Hasher
	to_hash = |value, hasher| value.clock.to_hash(value.date.to_hash(hasher))
	to_inspect : LocalDateTime -> Str
	to_inspect = |value| "LocalDateTime(${Str.inspect(value.date)}, ${Str.inspect(value.clock)})"

	expect {
		# Ordinary form input is a local position, not a resolved instant.
		value = parse_gregorian("2026-09-07T09:30")?
		Calendar.Date.to_fields(date(value)) == { year: 2026, month: 9, day: 7 } and
			ClockTime.to_microseconds_since_midnight(clock(value)) == 34200000000 and
				to_gregorian_text(value) == Ok("2026-09-07T09:30:00") and
					parse_gregorian("2026-09-07T09:30:00.120") == parse_gregorian("2026-09-07T09:30:00.12")
	}

	expect {
		# Explicit profiles cannot silently relabel the Julian leap date.
		julian = Calendar.Date.from_fields(Julian, { year: 1900, month: 2, day: 29 })?
		local = new(julian, ClockTime.from_microseconds_since_midnight(0)?)
		to_gregorian_text(local) == Err(UnsupportedCalendar(Julian)) and
			parse_gregorian("1900-02-29T00:00") == Err(InvalidDate(InvalidDay))
	}

	expect {
		# Local labels retain the full provider range before timeline lowering.
		first = parse_gregorian("-2147483648-01-01T00:00")?
		last = parse_gregorian("+2147483647-12-31T23:59:59.999999")?
		to_gregorian_text(first) == Ok("-2147483648-01-01T00:00:00") and
			to_gregorian_text(last) == Ok("+2147483647-12-31T23:59:59.999999")
	}

	expect {
		parse_gregorian("2026-09-07") == Err(Incomplete) and
			parse_gregorian("2026-09-07T") == Err(Incomplete) and
				parse_gregorian("T09:30") == Err(InvalidDate(Malformed)) and
					parse_gregorian("2026-09T09:30") == Err(InvalidDate(Malformed)) and
						parse_gregorian("2026-13-") == Err(InvalidDate(InvalidMonth)) and
							parse_gregorian("2026-09-07TT09:30") == Err(Malformed) and
								parse_gregorian("x".repeat(65)) == Err(TooLarge)
	}

	expect parse_gregorian("2026-09-07T9") == Err(InvalidTime(InvalidHour))
	expect parse_gregorian("2026-09-07T09:7") == Err(InvalidTime(InvalidMinute))
	expect parse_gregorian("2026-09-07T09:30:6") == Err(InvalidTime(InvalidSecond))

	expect {
		# Hinnant's independently sourced equal-day anchor, also exercised by
		# Calendar.Date and the generated Julian reference formula fixtures.
		julian = Calendar.Date.from_fields(Julian, { year: 1582, month: 10, day: 5 })?
		gregorian = Calendar.Date.from_fields(Gregorian, { year: 1582, month: 10, day: 15 })?
		time = ClockTime.from_fields({ hour: 12, minute: 30, second: 0, microsecond: 1 })?
		a = new(julian, time)
		b = new(gregorian, time)
		same_position(a, b) and a != b and in_calendar(a, Gregorian) == Ok(b)
	}

	expect {
		before = Calendar.Date.from_fields(Gregorian, { year: 1969, month: 12, day: 31 })?
		after = Calendar.Date.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
		last = ClockTime.from_microseconds_since_midnight(86399999999)?
		first = ClockTime.from_microseconds_since_midnight(0)?
		compare_position(new(before, last), new(after, first)) == LT and
			compare_position(new(after, first), new(before, last)) == GT
	}
}
