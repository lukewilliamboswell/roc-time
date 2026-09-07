app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.ScheduleDefinition
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence
import time.CalendarPattern
import time.Calendar
import time.GregorianDate
import time.ClockTime
import time.LocalDateTime
import time.PosixDelta
import time.PosixSpan
import DefinitionFixture

# R01/R11/R12/R15: definition construction normalizes supplied endings once.
# Reusing a definition for a new window must not sort them again or enumerate
# the Forever series. Requested-byte traffic is not live/retained memory.
# Inputs include a one-microsecond anchor and duplicate source definitions.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "4096") ?? 4096
	ownership = args.get(2) ?? "shared"
	horizon = I64.from_str(args.get(3) ?? "200000") ?? 200000
	ceiling = U64.from_str(args.get(4) ?? "1000000") ?? 1000000
	Host.assert!(count <= 4096 and horizon > 2000 and horizon <= 200000)
	anchor = DefinitionFixture.label(0)
	date = Calendar.Date.as_gregorian(LocalDateTime.date(anchor)) ?? crash "Gregorian anchor"
	end_date = GregorianDate.from_fields({ year: horizon, month: 1, day: 1 }) ?? crash "bounded horizon"
	end = LocalDateTime.new(Calendar.Date.from_gregorian(end_date), LocalDateTime.clock(anchor))
	rules = DefinitionFixture.rules({})
	rule = TimedRecurrence.new({ date, clock: LocalDateTime.clock(anchor) }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Forever, by_set_pos: [] }) ?? crash "valid native rule"
	before_input = Host.allocated_bytes!({})
	backing = DefinitionFixture.inputs(count + 2)
	retained = if ownership == "owned" {
		None
	} else {
		Some(backing)
	}
	shift = if ownership == "sliced" {
		1.U64
	} else {
		0.U64
	}
	inputs = backing.sublist({ start: shift, len: count })
	before_construct = Host.allocated_bytes!({})
	definition = ScheduleDefinition.from_native({ rule, duration: Coordinate(PosixDelta.from_microseconds(3600000000)), overrides: inputs, context: { rules, occurrence: RequireUnique, gap: RejectGap } }) ?? crash "valid schedule definition"
	after_construct = Host.allocated_bytes!({})
	Host.assert!(after_construct - before_construct <= ceiling)
	data = ScheduleDefinition.definition(definition)
	after_access = Host.allocated_bytes!({})
	Host.assert!(after_access == after_construct)
	match data {
		Native(value) => Host.assert!(TimedRecurrence.definition(value.rule).anchor == anchor and ClockTime.to_fields(LocalDateTime.clock(anchor)).microsecond == 1)
		ICal(_) => crash "native origin changed"
	}
	before_cursor = Host.allocated_bytes!({})
	cursor = ScheduleDefinition.cursor(42.U64, definition, { start: anchor, end }) ?? crash "valid window"
	after_cursor = Host.allocated_bytes!({})
	first = TimedSchedule.collect(cursor, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 8, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "first bounded occurrence"
	after_first = Host.allocated_bytes!({})
	Host.assert!(first.occurrences.len() == 1 and first.steps <= 8 and first.zone_segments <= 8)
	for value in first.occurrences {
		Host.assert!(TimedOccurrence.source(value) == anchor)
		width = if count == 0 {
			3600000000.I64
		} else {
			7200000000.I64
		}
		Host.assert!(PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(width)))
	}
	resume = match first.status {
		Limited(progress) => progress.cursor
		Complete => crash "Forever rule ended after one occurrence"
	}
	before_second = Host.allocated_bytes!({})
	second = TimedSchedule.collect(resume, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 8, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "resumed bounded occurrence"
	after_second = Host.allocated_bytes!({})
	Host.assert!(second.occurrences.len() == 1 and second.steps <= 8 and second.zone_segments <= 8)
	for value in second.occurrences {
		Host.assert!(TimedOccurrence.source(value) == DefinitionFixture.label(1))
		width = if count <= 1 {
			3600000000.I64
		} else {
			7200000000.I64
		}
		Host.assert!(PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(width)))
	}
	match retained {
		Some(original) => Host.assert!(original == DefinitionFixture.inputs(count + 2))
		None => {}
	}
	# Keep both the declaration and its semantic view live across consumption.
	Host.assert!(Str.inspect(definition).count_utf8_bytes() < 256)
	match data {
		Native(value) => Host.assert!(value.overrides.len() <= count)
		ICal(_) => crash "native origin changed"
	}
	{ bytes: "schedule-definition".to_utf8(), work: [before_construct - before_input, after_construct - before_construct, after_access - after_construct, after_cursor - before_cursor, after_first - after_cursor, after_second - before_second] }
}
