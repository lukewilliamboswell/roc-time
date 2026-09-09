import zones.Database
import time.ICalTimedRule
import time.ICalPeriod
import time.LocalDateTime
import time.OffsetTimestamp
import time.PosixSpan
import time.TimedRecurrence
import time.TimedOccurrence
import time.TimedSchedule
import time.ScheduleDefinition
import time.ZoneRules

## Exchange extracted iCalendar timed property values with explicit zone rules.
## The bundled database supplies a fixed, versioned Paris snapshot; no host zone
## or current clock is consulted. Export preserves the definition, not its source
## spelling, a full ICS document, or a native persistence archive. The feed's
## UTC cancellation matches the selected start while the meeting stays local.
MeetingExchange :: [].{
	render = || {
		imported = exchange(
			ICalTimedRule.parse({
				start: "20260322T090000",
				rule: "FREQ=WEEKLY;COUNT=4",
				duration: "PT1H",
				inclusions: [],
				exclusions: ["20260405T070000Z"],
				periods: [],
				mode: Zoned,
			}),
		)?
		definition = ICalTimedRule.definition(imported)
		extra = "20260330T090000/PT2H"
		edited = exchange(ICalTimedRule.new({ ..definition, periods: definition.periods.append(extra) }))?
		parts = exchange(ICalTimedRule.to_parts(edited))?
		restored = exchange(ICalTimedRule.parse(parts))?
		rules = ZoneRules.from_database(Database.get("Europe/Paris")?)?
		window = {
			start: local_text("2026-03-20T00:00")?,
			end: local_text("2026-04-15T00:00")?,
		}
		meeting = match ScheduleDefinition.from_ical({ rule: restored, context: Local(rules) }) {
			Ok(value) => value
			Err(error) => return Err(Definition(error))
		}
		schedule = ScheduleDefinition.cursor("team-meeting", meeting, window)?
		batch = match TimedSchedule.collect(
			schedule,
			{
				work: { max_steps: 1000, max_buffered: 32, max_zone_segments: 100000, max_zone_candidates: 8 },
				max_occurrences: 10,
			},
		) {
			Ok(value) => value
			Err(error) => return Err(Evaluation(error))
		}
		var $lines = [
			"Weekly Paris meeting exchange (extracted iCalendar property values)",
			"Imported UTC cancellation for 5 April; added a two-hour meeting on 30 March",
			"Canonical DTSTART value: ${parts.start}",
			"Canonical RRULE value: ${parts.rule}",
			"Canonical DURATION value: ${parts.duration}",
		]
		for value in parts.exclusions {
			$lines = $lines.append("Canonical EXDATE value: ${value}")
		}
		for value in parts.periods {
			$lines = $lines.append("Canonical RDATE PERIOD value: ${value}")
		}
		$lines = $lines.append("Reimported meetings in [2026-03-20, 2026-04-15), using Europe/Paris:")
		for occurrence in batch.occurrences {
			source = TimedOccurrence.source(occurrence)
			local = LocalDateTime.to_gregorian_text(source)?
			span = TimedOccurrence.span(occurrence)
			start = utc(PosixSpan.start(span))?
			end = utc(PosixSpan.end(span))?
			$lines = $lines.append("${local} Paris: ${start} -> ${end}")
		}
		match batch.status {
			Complete => {
				$lines = $lines.append("Complete: local 09:00 survives the clock change; COUNT is not replenished after exclusion.")
			}
			Limited(progress) => {
				$lines = $lines.append("Partial results: ${limit_text(progress.reason)}; retain the returned cursor to resume.")
			}
		}
		Ok($lines)
	}
}

utc = |boundary| {
	timestamp = match OffsetTimestamp.from_boundary(boundary, UnassertedUtc, 0) {
		Ok(value) => value
		Err(error) => return Err(TimestampOutput(error))
	}
	Ok(OffsetTimestamp.to_text(timestamp))
}

exchange = |result| match result {
	Ok(value) => Ok(value)
	Err(error) => Err(Exchange(error))
}

local_text = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(LocalInput(error))
}

limit_text = |reason| match reason {
	StartWorkLimit => "start work budget"
	StartBufferLimit => "start buffer budget"
	StartZoneWorkLimit => "start zone work budget"
	StartZoneBufferLimit => "start zone buffer budget"
	EndZoneWorkLimit => "end zone work budget"
	EndZoneBufferLimit => "end zone buffer budget"
	OutputLimit => "output budget"
}
