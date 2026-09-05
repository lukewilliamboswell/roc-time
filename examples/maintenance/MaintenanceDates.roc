import time.RfcDateRule
import time.DateRecurrence
import time.GregorianDate

## Review a contractor's date-only recurrence values within a planning window.
MaintenanceDates :: [].{
	upcoming = |contract, window| {
		rule = match RfcDateRule.parse(contract) {
			Ok(value) => value
			Err(error) => return Err(InvalidCalendar(error))
		}
		cursor = DateRecurrence.cursor(rule, window)?
		batch = DateRecurrence.Cursor.collect(cursor, { max_steps: 10000, max_buffered: 366, max_occurrences: 100 })?
		match batch.status {
			Complete => Ok(batch.dates)
			Limited(progress) => Err(PlanningLimit(progress.reason))
		}
	}
	display = |date| {
		fields = GregorianDate.to_fields(date)
		"${fields.year.to_str()}-${pad(fields.month)}-${pad(fields.day)}"
	}
}

pad = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
