import time.CalendarPattern
import time.GregorianDate
import time.CivilDay
import time.DateRecurrence

## Plan equipment inspections on the last Tuesday every three months.
InspectionDates :: [].{
	for_year = |year| {
		february = GregorianDate.from_fields({ year, month: 2, day: 1 })?
		spec = { ..CalendarPattern.defaults(Monthly), interval: 3, by_day: [{ ordinal: -1, weekday: Tuesday }] }
		pattern = CalendarPattern.new(february, spec)?
		# Find the first actual inspection date, which anchors the series.
		frame = CalendarPattern.period(pattern, 0)?
		var day = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.start))
		end = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.end))
		var first = None
		while day < end {
			date = GregorianDate.from_civil_day(CivilDay.from_day_number(day))?
			if CalendarPattern.matches(pattern, 0, date)? {
				first = Some(date)
			}
			day = day + 1
		}
		anchor = match first {
			Some(date) => date
			None => return Err(NoInspectionDate)
		}
		rule = DateRecurrence.new(anchor, { pattern: spec, termination: Count(4), by_set_pos: [], inclusions: [], exclusions: [] })?
		window_end = GregorianDate.from_fields({ year, month: 12, day: 1 })?
		cursor = DateRecurrence.cursor(rule, { start: february, end: window_end })?
		batch = DateRecurrence.Cursor.collect(cursor, { max_steps: 1000, max_buffered: 31, max_occurrences: 4 })?
		match batch.status {
			Complete => Ok(batch.dates)
			Limited(progress) => Err(InspectionLimit(progress.reason))
		}
	}

	display = |date| {
		fields = GregorianDate.to_fields(date)
		"${fields.year.to_str()}-${pad(fields.month)}-${pad(fields.day)}"
	}
}

pad = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
