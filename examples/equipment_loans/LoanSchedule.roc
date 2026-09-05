import time.CalendarPattern
import time.CalendarDate
import time.CalendarDelta
import time.ClockTime
import time.GregorianDate
import time.LocalDateTime
import time.PosixDelta
import time.PosixSpan
import time.TimedRecurrence
import time.TimedOccurrence

## Two monthly loan starts on the 31st; each loan lasts one calendar month.
## Clamping the return date must not change the next scheduled start.
LoanSchedule :: [].{
	upcoming = |rules| {
		date = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
		clock = ClockTime.from_fields({ hour: 9, minute: 0, second: 0, microsecond: 0 })?
		start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
		end_date = GregorianDate.from_fields({ year: 2025, month: 4, day: 1 })?
		end = LocalDateTime.new(CalendarDate.from_gregorian(end_date), clock)
		rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Monthly), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
		cursor = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap })?
		batch = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 10000, max_buffered: 1, max_zone_segments: 100000, max_zone_candidates: 2 }, max_occurrences: 3 })?
		match batch.status {
			Complete => {}
			Limited(progress) => return Err(ScheduleLimit(progress.reason))
		}
		var loans = []
		for source in batch.occurrences {
			id = TimedRecurrence.Occurrence.source(source)
			pending = TimedOccurrence.cursor(id, source, Calendar({ delta: CalendarDelta.months(1), invalid_date: Clamp, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }))?
			result = TimedOccurrence.Cursor.collect(pending, { max_segments: 100000, max_candidates: 2 })?
			match result.status {
				Complete(loan) => {
					loans = loans.append(loan)
				}
				Limited(progress) => return Err(ReturnDateLimit(progress.reason))
			}
		}
		Ok(loans)
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
