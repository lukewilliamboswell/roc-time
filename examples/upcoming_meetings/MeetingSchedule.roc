import time.ICalendar.TimedRule as ICalTimedRule
import time.ScheduleDefinition

import time.LocalDateTime

## Prepare one reusable declaration; each bounded query preserves its whole batch.
MeetingSchedule :: [].{
	prepare = |rules, parts| {
		rule = match ICalTimedRule.parse(parts) {
			Ok(value) => value
			Err(error) => return Err(Input(error))
		}
		match ScheduleDefinition.from_ical({ rule, context: Local(rules) }) {
			Ok(value) => Ok(value)
			Err(error) => Err(Definition(error))
		}
	}
	query = |meeting, series, window, limits| {
		cursor = match meeting.cursor({ series, window }) {
			Ok(value) => value
			Err(error) => return Err(Window(error))
		}
		match ScheduleDefinition.Cursor.collect(cursor, limits) {
			Ok(value) => Ok(value)
			Err(error) => Err(Evaluation(error))
		}
	}
	resume = |cursor, limits| match ScheduleDefinition.Cursor.collect(cursor, limits) {
		Ok(value) => Ok(value)
		Err(error) => Err(Evaluation(error))
	}
	local = |text| match LocalDateTime.parse_gregorian(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(LocalInput(error))
	}
	describe = |item| LocalDateTime.to_gregorian_text(ScheduleDefinition.Occurrence.source(item))
}
