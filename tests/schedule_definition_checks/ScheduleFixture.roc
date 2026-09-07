import time.ICalTimedRule
import time.ICalPeriod
import time.ScheduleDefinition
import time.ZoneRules
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.LocalDateTime
import time.TimedSchedule
import time.TimedRecurrence

## Fixed synthetic interpretation context and bounded scheduling helpers.
ScheduleFixture :: [].{
	rules = |offset| {
		validity = PosixSpan.from_seconds(-2000000, 2000000, RejectSubmicrosecond)?
		ZoneRules.new_bounded("Synthetic/Meeting", "fixture-v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(offset) }], { minimum: 0, maximum: 3600 })
	}
	meeting = |zone| {
		imported = import_parts({ start: "19691225T090000", rule: "FREQ=WEEKLY;COUNT=4", duration: "PT1H", mode: Zoned, inclusions: [], exclusions: [], periods: [] })?
		parts = ICalTimedRule.definition(imported)
		revised = TimedRecurrence.with_exclusions(parts.rule, [local("1970-01-08T09:00")?])?
		extra : ICalPeriod
		extra = "19700102T090000/PT2H"
		rule = match ICalTimedRule.new({ ..parts, rule: revised, periods: [extra] }) {
			Ok(value) => value
			Err(error) => return Err(Interchange(error))
		}
		match ScheduleDefinition.from_ical({ rule, context: Local(zone) }) {
			Ok(value) => Ok(value)
			Err(error) => Err(Definition(error))
		}
	}
	collect = |record, start, end| {
		window = { start: local(start)?, end: local(end)? }
		cursor = ScheduleDefinition.cursor(record.series_id, record.definition, window)?
		match TimedSchedule.collect(cursor, { work: { max_steps: 1000, max_buffered: 32, max_zone_segments: 100, max_zone_candidates: 2 }, max_occurrences: 10 }) {
			Ok(value) => Ok(value)
			Err(error) => Err(Evaluation(error))
		}
	}
}

local = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(LocalInput(error))
}

import_parts = |parts| match ICalTimedRule.parse(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(Interchange(error))
}
