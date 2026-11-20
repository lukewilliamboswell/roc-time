import time.Recurrence
import time.GregorianDate

## Plan equipment inspections on the last Tuesday every three months.
InspectionDates :: [].{
	for_year = |year| {
		february = GregorianDate.from_fields({ year, month: 2, day: 1 })?
		series = Recurrence.Date.from_pattern(
			february,
			{
				pattern: { ..Recurrence.CalendarPattern.defaults(Monthly), interval: 3, by_day: [{ ordinal: -1, weekday: Tuesday }] },
				termination: Count(4),
				start_policy: FromSeed,
			},
		)?
		window_end = GregorianDate.from_fields({ year, month: 12, day: 1 })?
		cursor = series.cursor({ start: february, end: window_end })?
		batch = cursor.collect({ max_steps: 1000, max_buffered: 31, max_occurrences: 4 })?
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
