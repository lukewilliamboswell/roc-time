import time.CalendarPattern
import time.CalendarDate
import time.CalendarDelta
import time.ClockTime
import time.GregorianDate
import time.LocalDateTime
import time.PosixDelta
import time.PosixSpan
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence

## Monthly starts last one calendar month; an extra booking lasts one week.
## Clamping the return date must not change the next scheduled start.
LoanSchedule :: [].{
	upcoming = |rules| {
		date = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
		clock = ClockTime.from_fields({ hour: 9, minute: 0, second: 0, microsecond: 0 })?
		start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
		end_date = GregorianDate.from_fields({ year: 2025, month: 4, day: 1 })?
		end = LocalDateTime.new(CalendarDate.from_gregorian(end_date), clock)
		monthly = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Monthly), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
		extra_date = GregorianDate.from_fields({ year: 2025, month: 2, day: 14 })?
		rule = TimedRecurrence.with_inclusions(monthly, [{ date: extra_date, clock }])?
		series : Str
		series = "equipment-loans"
		monthly_duration : TimedOccurrence.Duration
		monthly_duration = Calendar({ delta: CalendarDelta.months(1), invalid_date: Clamp, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
		extra_duration : TimedOccurrence.Duration
		extra_duration = Calendar({ delta: CalendarDelta.days(7), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
		overrides = [{ source: LocalDateTime.new(CalendarDate.from_gregorian(extra_date), clock), duration: extra_duration }]
		cursor = TimedSchedule.new_with_overrides(series, rule, { start, end }, monthly_duration, overrides, { rules, occurrence: RequireUnique, gap: RejectGap })?
		batch = match TimedSchedule.collect(cursor, { work: { max_steps: 10000, max_buffered: 2, max_zone_segments: 100000, max_zone_candidates: 2 }, max_occurrences: 4 }) {
			Ok(value) => value
			Err(error) => return Err(Interpretation(error))
		}
		match batch.status {
			Complete => Ok(batch.occurrences)
			Limited(progress) => Err(ScheduleLimit(progress.reason))
		}
	}
	report = |loan| {
		start = TimedRecurrence.Occurrence.source(TimedOccurrence.start(loan))
		end = match TimedOccurrence.calendar_anchor(loan) {
			Some(anchor) => anchor.source
			None => return Err(MissingCalendarReturnDate)
		}
		width = PosixDelta.to_microseconds(PosixSpan.coordinate_width(TimedOccurrence.span(loan))?)
		if I64.rem_by(width, 3600000000) != 0 {
			return Err(FractionalHours)
		}
		hours = I64.div_trunc_by(width, 3600000000)
		Ok("${display(start)} -> ${display(end)} (${hours.to_str()} POSIX hours)\n")
	}
}

display = |value| {
	date = CalendarDate.to_fields(LocalDateTime.date(value))
	clock = ClockTime.to_fields(LocalDateTime.clock(value))
	"${date.year.to_str()}-${pad(date.month)}-${pad(date.day)} ${pad(clock.hour)}:${pad(clock.minute)}"
}

pad = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
