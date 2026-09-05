import time.RfcDateRule
import time.AllDayRecurrence
import time.AllDayOccurrence
import time.Coverage
import time.PosixDelta
import time.GregorianDate

## Review a contractor's date-only recurrence values within a planning window.
MaintenanceDates :: [].{
	upcoming = |contract, window, rules| {
		rule = match RfcDateRule.parse(contract) {
			Ok(value) => value
			Err(error) => return Err(InvalidCalendar(error))
		}
		cursor = AllDayRecurrence.new("service-contract", rule, window, 1, rules)?
		batch = match AllDayRecurrence.collect(cursor, { work: { max_date_steps: 10000, max_date_buffered: 366, max_zone_segments: 10000, max_zone_members: 8 }, max_occurrences: 100 }) {
			Ok(value) => value
			Err(error) => return Err(ResolutionFailed(error))
		}
		match batch.status {
			Complete => Ok(batch.occurrences)
			Limited(progress) => Err(PlanningLimit(progress.reason))
		}
	}
	report_visit = |visit| {
		width = Coverage.coordinate_width(AllDayOccurrence.coverage(visit))?
		micros = PosixDelta.to_microseconds(width)
		if I64.rem_by(micros, 3600000000) != 0 {
			return Err(FractionalCoverageHours)
		}
		hours = I64.div_trunc_by(micros, 3600000000)
		Ok("${display(AllDayOccurrence.id(visit).date)}: ${hours.to_str()} hours of local-day coverage\n")
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
