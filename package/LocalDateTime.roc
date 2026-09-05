import Calendar
import CalendarDate
import CivilDay
import ClockTime

## A dated local label. A zone occurrence has not been selected or resolved.
##
## Example
##
## Combine a calendar date with a wall-clock label before choosing a timezone.
## Construction alone does not resolve daylight-saving gaps or folds.
##
## ```roc
## import time.GregorianDate
## import time.CalendarDate
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
##     local = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
##     ClockTime.to_fields(LocalDateTime.clock(local)).hour == 9
## }
## ```
##
## Examples assume a package dependency named `time`.
LocalDateTime :: { date : CalendarDate, clock : ClockTime }.{
	new : CalendarDate, ClockTime -> LocalDateTime
	new = |date, clock| { date, clock }

	date : LocalDateTime -> CalendarDate
	date = |value| value.date
	clock : LocalDateTime -> ClockTime
	clock = |value| value.clock

	in_calendar : LocalDateTime, Calendar -> Try(LocalDateTime, [OutOfRange, ..])
	in_calendar = |value, target| {
		converted = CalendarDate.in_calendar(value.date, target)?
		Ok(new(converted, value.clock))
	}

	## Compare local positions, not timeline occurrences or descriptions.
	compare_position : LocalDateTime, LocalDateTime -> [LT, EQ, GT]
	compare_position = |a, b| {
		days = CivilDay.compare(CalendarDate.to_civil_day(a.date), CalendarDate.to_civil_day(b.date))
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
		# Hinnant's independently sourced equal-day anchor, also exercised by
		# CalendarDate and the generated Julian reference formula fixtures.
		julian = CalendarDate.from_fields(Julian, { year: 1582, month: 10, day: 5 })?
		gregorian = CalendarDate.from_fields(Gregorian, { year: 1582, month: 10, day: 15 })?
		time = ClockTime.from_fields({ hour: 12, minute: 30, second: 0, microsecond: 1 })?
		a = new(julian, time)
		b = new(gregorian, time)
		same_position(a, b) and a != b and in_calendar(a, Gregorian) == Ok(b)
	}

	expect {
		before = CalendarDate.from_fields(Gregorian, { year: 1969, month: 12, day: 31 })?
		after = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
		last = ClockTime.from_microseconds_since_midnight(86399999999)?
		first = ClockTime.from_microseconds_since_midnight(0)?
		compare_position(new(before, last), new(after, first)) == LT and
			compare_position(new(after, first), new(before, last)) == GT
	}
}
