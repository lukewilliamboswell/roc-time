import time.CalendarPattern
import time.CalendarDate
import time.ClockTime
import time.GregorianDate
import time.LocalDateTime
import time.TimedRecurrence
import time.FixedOffset

## Four monthly dispatch deadlines: the final Monday's final pickup slot.
DispatchDeadlines :: [].{
	upcoming = |rules, window| {
		date = GregorianDate.from_fields({ year: 2025, month: 1, day: 27 })?
		clock = ClockTime.from_fields({ hour: 17, minute: 0, second: 0, microsecond: 0 })?
		rule = TimedRecurrence.new(
			{ date, clock },
			{
				calendar: { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] },
				clocks: { hours: [9, 17], minutes: [], seconds: [] },
				termination: Count(4),
				by_set_pos: [-1],
			},
		)?
		cursor = TimedRecurrence.cursor(rule, window, { rules, occurrence: RequireUnique, gap: RejectGap })?
		batch = TimedRecurrence.Cursor.collect(
			cursor,
			{
				work: { max_steps: 10000, max_buffered: 10, max_zone_segments: 100000, max_zone_candidates: 2 },
				max_occurrences: 5,
			},
		)?
		match batch.status {
			Complete => Ok(batch.occurrences)
			Limited(progress) => Err(PlanningLimit(progress.reason))
		}
	}
	report = |deadline| {
		source = TimedRecurrence.Occurrence.source(deadline)
		utc = FixedOffset.project(FixedOffset.from_seconds(0), TimedRecurrence.Occurrence.boundary(deadline), Gregorian)?
		Ok("${display(source)} Melbourne / ${display(utc)} UTC\n")
	}
	midnight = |year, month, day| {
		date = GregorianDate.from_fields({ year, month, day })?
		clock = ClockTime.from_microseconds_since_midnight(0)?
		Ok(LocalDateTime.new(CalendarDate.from_gregorian(date), clock))
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
