import Calendar
import CalendarDate
import CivilDay
import ClockTime
import LocalDateTime
import PosixBoundary

## Explicit local-minus-POSIX offset in whole seconds. No named-zone rules.
##
## Example
##
## Offsets are local minus timeline, in whole seconds. A fixed offset does not
## model daylight-saving transitions; use `ZoneRules` for named zones.
##
## ```roc
## import time.FixedOffset
## import time.PosixBoundary
## import time.LocalDateTime
## import time.ClockTime
##
## expect {
##     local = FixedOffset.project(
##         FixedOffset.from_seconds(3600),
##         PosixBoundary.from_microseconds(0), Gregorian,
##     )?
##     ClockTime.to_fields(LocalDateTime.clock(local)).hour == 1
## }
## ```
##
## Examples assume a package dependency named `time`.
FixedOffset :: [Seconds(I32)].{
	from_seconds : I32 -> FixedOffset
	from_seconds = |seconds| Seconds(seconds)
	to_seconds : FixedOffset -> I32
	to_seconds = |Seconds(seconds)| seconds

	resolve : FixedOffset, LocalDateTime -> Try(PosixBoundary, [OutOfRange, ..])
	resolve = |Seconds(seconds), local| {
		day = CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(local)))
		clock = ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(local))
		# Provider days fit I64; multiplication and subtraction fit I128.
		# Narrow only after subtracting the offset, preserving endpoint cases.
		number = day.to_i128() * 86400000000 + clock.to_i128() - seconds.to_i128() * 1000000
		match I128.to_i64_try(number) {
			Ok(micros) => Ok(PosixBoundary.from_microseconds(micros))
			Err(_) => Err(OutOfRange)
		}
	}

	project : FixedOffset, PosixBoundary, Calendar -> Try(LocalDateTime, [OutOfRange, ..])
	project = |Seconds(seconds), boundary, calendar| {
		number = PosixBoundary.to_microseconds(boundary).to_i128() + seconds.to_i128() * 1000000
		day = I128.div_floor_by(number, 86400000000)
		# Floor division gives a nonnegative clock remainder, even before epoch.
		clock_number = number - day * 86400000000
		day_number = I128.to_i64_try(day)?
		micros = I128.to_i64_try(clock_number)?
		date = CalendarDate.from_civil_day(calendar, CivilDay.from_day_number(day_number))?
		clock = ClockTime.from_microseconds_since_midnight(micros)?
		Ok(LocalDateTime.new(date, clock))
	}

	is_eq : FixedOffset, FixedOffset -> Bool
	is_eq = |Seconds(a), Seconds(b)| a == b
	to_hash : FixedOffset, Hasher -> Hasher
	to_hash = |Seconds(seconds), hasher| seconds.to_hash(hasher)
	to_inspect : FixedOffset -> Str
	to_inspect = |Seconds(seconds)| "FixedOffset(${seconds.to_str()} seconds local-minus-POSIX)"

	expect {
		# RFC 3339 section 4.2: 18:50 at -04:00 equals 22:50 at zero.
		# https://www.rfc-editor.org/rfc/rfc3339#section-4.2 (July 2002).
		date = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
		clock = ClockTime.from_fields({ hour: 18, minute: 50, second: 0, microsecond: 0 })?
		resolve(from_seconds(-14400), LocalDateTime.new(date, clock)) ==
			Ok(PosixBoundary.from_microseconds(82200000000))
	}

	expect {
		# RFC 5545 §3.3.5 and verified erratum 4271: New York's nonexistent
		# 2007-03-11 02:30 uses the pre-gap -05:00 offset, yielding 07:30 UTC
		# (03:30 under -04:00). This validates conversion primitives, not an
		# implemented automatic gap policy or timed recurrence adapter.
		# https://www.rfc-editor.org/errata/eid4271
		date = CalendarDate.from_fields(Gregorian, { year: 2007, month: 3, day: 11 })?
		clock = ClockTime.from_fields({ hour: 2, minute: 30, second: 0, microsecond: 0 })?
		utc_clock = ClockTime.from_fields({ hour: 7, minute: 30, second: 0, microsecond: 0 })?
		adjusted_clock = ClockTime.from_fields({ hour: 3, minute: 30, second: 0, microsecond: 0 })?
		original = LocalDateTime.new(date, clock)
		boundary = resolve(from_seconds(-18000), original)?
		boundary == resolve(from_seconds(0), LocalDateTime.new(date, utc_clock))? and
			project(from_seconds(-14400), boundary, Gregorian)? == LocalDateTime.new(date, adjusted_clock)
	}

	expect {
		local = project(from_seconds(0), PosixBoundary.from_microseconds(-1), Gregorian)?
		CalendarDate.to_fields(LocalDateTime.date(local)) == { year: 1969, month: 12, day: 31 } and
			ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(local)) == 86399999999
	}

	expect {
		var valid = Bool.True
		for number in [I64.lowest, -1, 0, 1, I64.highest] {
			for seconds in [I32.lowest, -1, 0, 1, I32.highest] {
				offset = from_seconds(seconds)
				for calendar in [Gregorian, Julian] {
					boundary = PosixBoundary.from_microseconds(number)
					local = project(offset, boundary, calendar)?
					valid = valid and resolve(offset, local) == Ok(boundary)
				}
			}
		}
		valid
	}

	expect {
		local = project(from_seconds(1), PosixBoundary.from_microseconds(I64.highest), Gregorian)?
		resolve(from_seconds(0), local) == Err(OutOfRange)
	}
}
