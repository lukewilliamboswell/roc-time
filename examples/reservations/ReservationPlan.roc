import time.RfcDateTime
import time.RfcTimedRule
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence
import time.PosixSpan
import time.PosixDelta
import time.LocalDateTime
import time.CalendarDate

## Import individual PERIOD values as additions and exceptions to a UTC series.
ReservationPlan :: [].{
	upcoming = |inputs| {
		start = match RfcDateTime.parse(inputs.query_start) {
			Ok(value) => value
			Err(error) => return Err(Timestamp(error))
		}
		end = match RfcDateTime.parse(inputs.query_end) {
			Ok(value) => value
			Err(error) => return Err(Timestamp(error))
		}
		rule = match RfcTimedRule.parse({ start: inputs.start, rule: inputs.rule, mode: Utc, duration: inputs.duration, inclusions: [], exclusions: [], periods: inputs.periods }) {
			Ok(value) => value
			Err(error) => return Err(Recurrence(error))
		}
		cursor = RfcTimedRule.schedule("equipment", rule, { start: RfcDateTime.local_label(start), end: RfcDateTime.local_label(end) }, Utc)?
		batch = match TimedSchedule.collect(cursor, { work: { max_steps: 100, max_buffered: 2, max_zone_segments: 20, max_zone_candidates: 1 }, max_occurrences: 10 }) {
			Ok(value) => value
			Err(error) => return Err(Interpretation(error))
		}
		match batch.status {
			Complete => Ok(batch.occurrences)
			Limited(progress) => Err(NeedMoreWork(progress.reason))
		}
	}
	report = |reservation| {
		source = TimedRecurrence.Occurrence.source(TimedOccurrence.start(reservation))
		date = CalendarDate.to_fields(LocalDateTime.date(source))
		width = PosixSpan.coordinate_width(TimedOccurrence.span(reservation))?
		micros = PosixDelta.to_microseconds(width)
		if I64.rem_by(micros, 60000000) != 0 {
			return Err(FractionalMinutes)
		}
		minutes = micros // 60000000
		Ok("January ${date.day.to_str()}: ${minutes.to_str()} POSIX minutes\n")
	}
}
