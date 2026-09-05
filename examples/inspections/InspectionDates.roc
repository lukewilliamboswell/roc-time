import time.CalendarPattern
import time.GregorianDate
import time.CivilDay

## Plan equipment inspections on the last Tuesday every three months.
InspectionDates :: [].{
	for_year = |year| {
		anchor = GregorianDate.from_fields({ year, month: 2, day: 1 })?
		spec = { ..CalendarPattern.defaults(Monthly), interval: 3, by_day: [{ ordinal: -1, weekday: Tuesday }] }
		pattern = CalendarPattern.new(anchor, spec)?
		var dates = []
		# Four explicitly requested periods, not a recurring-series COUNT.
		for index in [0.U64, 1, 2, 3] {
			frame = CalendarPattern.period(pattern, index)?
			var day = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.start))
			end = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.end))
			while day < end {
				date = GregorianDate.from_civil_day(CivilDay.from_day_number(day))?
				if CalendarPattern.matches(pattern, index, date)? {
					dates = dates.append(date)
				}
				day = day + 1
			}
		}
		Ok(dates)
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
