import time.Recurrence.CalendarPattern as CalendarPattern
import time.Calendar
import time.ClockTime
import time.GregorianDate
import time.LocalDateTime
import time.PosixDelta
import time.PosixSpan
import time.Recurrence.Timed as TimedRecurrence
import time.ScheduleDefinition

## Monthly starts last one calendar month; an extra booking lasts one week.
## Clamping the return date must not change the next scheduled start.
LoanSchedule :: [].{
	upcoming = |rules| {
		date = GregorianDate.from_fields({ year: 2025, month: 1, day: 31 })?
		clock = ClockTime.from_fields({ hour: 9, minute: 0, second: 0, microsecond: 0 })?
		start = LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock })
		end_date = GregorianDate.from_fields({ year: 2025, month: 4, day: 1 })?
		end = LocalDateTime.new({ date: Calendar.Date.from_gregorian(end_date), clock })
		extra_date = GregorianDate.from_fields({ year: 2025, month: 2, day: 14 })?
		extra = LocalDateTime.new({ date: Calendar.Date.from_gregorian(extra_date), clock })
		rule = TimedRecurrence.from_calendar(
			{ date, clock },
			{
				calendar: CalendarPattern.defaults(Monthly),
				termination: Count(2),
				inclusions: [extra],
			},
		)?
		series : Str
		series = "equipment-loans"
		monthly_duration : ScheduleDefinition.Occurrence.Duration
		monthly_duration = Calendar({ delta: Calendar.Delta.months(1), invalid_date: Clamp, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
		extra_duration : ScheduleDefinition.Occurrence.Duration
		extra_duration = Calendar({ delta: Calendar.Delta.days(7), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
		overrides = [{ source: LocalDateTime.new({ date: Calendar.Date.from_gregorian(extra_date), clock }), ending: After(extra_duration) }]
		definition = ScheduleDefinition.from_native({ rule, duration: monthly_duration, overrides, context: { rules, occurrence: RequireUnique, gap: RejectGap } })?
		cursor = definition.cursor({ series, window: { start, end } })?
		batch = match ScheduleDefinition.Cursor.collect(cursor, { work: { max_steps: 10000, max_buffered: 2, max_zone_segments: 100000, max_zone_candidates: 2 }, max_occurrences: 4 }) {
			Ok(value) => value
			Err(error) => return Err(Interpretation(error))
		}
		match batch.status {
			Complete => Ok(batch.occurrences)
			Limited(progress) => Err(ScheduleLimit(progress.reason))
		}
	}
	report = |loan| {
		start = loan.source()
		end = match ScheduleDefinition.Occurrence.calendar_anchor(loan) {
			Some(anchor) => anchor.source
			None => return Err(MissingCalendarReturnDate)
		}
		width = PosixDelta.to_microseconds(PosixSpan.coordinate_width(ScheduleDefinition.Occurrence.span(loan))?)
		if I64.rem_by(width, 3600000000) != 0 {
			return Err(FractionalHours)
		}
		hours = I64.div_trunc_by(width, 3600000000)
		Ok("${display(start)} -> ${display(end)} (${hours.to_str()} POSIX hours)\n")
	}
}

display = |value| {
	date = Calendar.Date.to_fields(LocalDateTime.date(value))
	clock = ClockTime.to_fields(LocalDateTime.clock(value))
	"${date.year.to_str()}-${pad(date.month)}-${pad(date.day)} ${pad(clock.hour)}:${pad(clock.minute)}"
}

pad = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
