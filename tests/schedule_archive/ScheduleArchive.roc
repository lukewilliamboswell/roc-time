import time.ICalTimedRule
import time.ICalPeriod
import time.ScheduleDefinition
import time.Persistence
import time.ZoneRules
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.LocalDateTime
import time.TimedSchedule
import time.TimedOccurrence
import time.TimedRecurrence
import time.OffsetTimestamp

## An application owns its series identifier; the library archive owns the
## temporal definition and complete immutable interpretation data. This example
## uses deliberately synthetic rules, not an IANA zone or historical claim.
ScheduleArchive :: [].{
	Envelope : { series_id : Str, archive : Str }
	Record : { series_id : Str, definition : ScheduleDefinition }
	save : Str, ScheduleDefinition -> Try(Str, [ArchiveConstruction(Persistence.Error), ..])
	save = |series_id, definition| {
		persisted = match Persistence.new(ScheduleDefinition(definition)) {
			Ok(value) => value
			Err(error) => return Err(ArchiveConstruction(error))
		}
		Ok(Json.to_str({ series_id, archive: Persistence.to_text(persisted) }))
	}
	load : Str -> Try(Record, [ArchiveInput(Persistence.Error), ApplicationJson([InvalidJson(Str), MissingRequiredField(Str), Encoding([InvalidJson(Str)])]), WrongArchiveKind, ..])
	load = |text| {
		record : Envelope
		record = match Json.parse(text) {
			Ok(value) => value
			Err(error) => return Err(ApplicationJson(error))
		}
		archived = match Persistence.parse(record.archive) {
			Ok(value) => value
			Err(error) => return Err(ArchiveInput(error))
		}
		match Persistence.value(archived) {
			ScheduleDefinition(definition) => Ok({ series_id: record.series_id, definition })
			_ => Err(WrongArchiveKind)
		}
	}
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
	render = || {
		definition = meeting(rules(3600)?)?
		json = save("team-weekly", definition)?
		restored = load(json)?
		var $lines = ["Saved and loaded meeting definition with its immutable synthetic zone", "Application series: ${restored.series_id}", "Weekly COUNT=4; exclude 8 January; add a two-hour 2 January meeting"]
		for start in ["1969-12-24T00:00", "1970-01-01T00:00"] {
			$lines = $lines.append("Window [${start}, 1970-01-16T00:00):")
			batch = collect(restored, start, "1970-01-16T00:00")?
			for occurrence in batch.occurrences {
				source = LocalDateTime.to_gregorian_text(TimedRecurrence.Occurrence.source(TimedOccurrence.start(occurrence)))?
				span = TimedOccurrence.span(occurrence)
				first = utc(PosixSpan.start(span))?
				last = utc(PosixSpan.end(span))?
				$lines = $lines.append("${source} local: ${first} -> ${last}")
			}
			match batch.status {
				Complete => {
					$lines = $lines.append("Complete; COUNT remains anchored to the original series.")
				}
				Limited(_) => {
					$lines = $lines.append("Partial results; retain the returned cursor and resume with an explicit budget.")
				}
			}
		}
		Ok($lines)
	}
}

local = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(LocalInput(error))
}

utc = |point| {
	value = match OffsetTimestamp.from_boundary(point, UnassertedUtc, 0) {
		Ok(stamp) => stamp
		Err(error) => return Err(Timestamp(error))
	}
	Ok(OffsetTimestamp.to_text(value))
}

import_parts = |parts| match ICalTimedRule.parse(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(Interchange(error))
}
