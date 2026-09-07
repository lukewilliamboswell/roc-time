app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.CalendarPattern
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence
import time.PosixSpan
import time.PosixDelta
import time.LocalDateTime
import time.ICalDuration
import time.ICalTimedRule
import ExportFixture

# R11/R12/R14/R15. Input, native construction, definition access, wrapper construction, export and
# first/resumed consumption have separate allocation scopes. Requested bytes
# are allocation traffic, not live or retained memory. Effects observe results.
# Duration parsing and round-trip parsing are outside the measured scopes.
# The zero-allocation accessor assertion covers this calendar pattern only;
# subdaily definition access may materialize weekday filter descriptions.
# Wrapper construction validates canonical byte limits, so its rendering traffic
# is measured independently from the requested export.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "4096") ?? 4096
	ownership = args.get(2) ?? "shared"
	horizon = I64.from_str(args.get(3) ?? "200000") ?? 200000
	ceiling = U64.from_str(args.get(4) ?? "2000000") ?? 2000000
	Host.assert!(count <= 4096 and horizon > 2000 and horizon <= 200000)
	anchor = ExportFixture.local(2000, 1)
	end = ExportFixture.local(horizon, 1)
	duration = match ICalDuration.parse(args.get(5) ?? "PT1H") {
		Ok(value) => value
		Err(_) => crash "valid duration"
	}
	before_input = Host.allocated_bytes!({})
	backing = ExportFixture.months(count + 2)
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
	months = backing.sublist({ start: shift, len: count })
	before_construct = Host.allocated_bytes!({})
	rule = match TimedRecurrence.new({ date: ExportFixture.date(2000, 1), clock: LocalDateTime.clock(anchor) }, { calendar: { ..CalendarPattern.defaults(Daily), by_month: months }, clocks: { hours: [], minutes: [], seconds: [] }, termination: Forever, by_set_pos: [] }) {
		Ok(value) => value
		Err(_) => crash "valid unbounded timed rule"
	}
	before_access = Host.allocated_bytes!({})
	definition = TimedRecurrence.definition(rule)
	Host.assert!(
		definition.anchor == anchor and definition.termination == Forever and (match definition.pattern {
			Calendar(value) => value.by_month.len() == count
			Subdaily(_) => Bool.False
		}),
	)
	retained_definition = if ownership == "owned" {
		None
	} else {
		Some(definition)
	}
	before_wrapper = Host.allocated_bytes!({})
	Host.assert!(before_wrapper == before_access)
	wrapper = match ICalTimedRule.new({ rule, duration, periods: [], mode: Utc }) {
		Ok(value) => value
		Err(_) => crash "valid wrapper"
	}
	before_export = Host.allocated_bytes!({})
	parts = match ICalTimedRule.to_parts(wrapper) {
		Ok(value) => value
		Err(_) => crash "valid timed export"
	}
	after_export = Host.allocated_bytes!({})
	Host.assert!(after_export - before_export <= ceiling)
	expected = if count == 0 {
		"FREQ=DAILY;INTERVAL=1;BYHOUR=0;BYMINUTE=0;BYSECOND=0;WKST=MO"
	} else if count == 1 {
		"FREQ=DAILY;INTERVAL=1;BYMONTH=1;BYHOUR=0;BYMINUTE=0;BYSECOND=0;WKST=MO"
	} else {
		"FREQ=DAILY;INTERVAL=1;BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12;BYHOUR=0;BYMINUTE=0;BYSECOND=0;WKST=MO"
	}
	Host.assert!(parts.start == "20000101T000000Z" and parts.duration == "PT3600S" and parts.rule == expected and parts.inclusions.is_empty() and parts.exclusions.is_empty())
	match retained_definition {
		Some(original) => Host.assert!((match original.pattern {
			Calendar(value) => value.by_month == ExportFixture.months(count + 2).sublist({ start: shift, len: count })
			Subdaily(_) => Bool.False
		}))
		None => {}
	}
	match retained {
		Some(original) => Host.assert!(original.len() == count + 2 and original.get(0) == Ok(1))
		None => {}
	}
	# The same saved declaration feeds a small window and a two-hundred-thousand-year window;
	# both must yield the same first two dates within a small work allowance.
	restored = match ICalTimedRule.parse(parts) {
		Ok(value) => value
		Err(_) => crash "resource export cannot be restored"
	}
	before_cursor = Host.allocated_bytes!({})
	cursor = match ICalTimedRule.schedule(1.U64, restored, { start: anchor, end }, Utc) {
		Ok(value) => value
		Err(_) => crash "valid resource window"
	}
	after_cursor = Host.allocated_bytes!({})
	first = match TimedSchedule.collect(cursor, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 8, max_zone_candidates: 1 }, max_occurrences: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded first date"
	}
	after_first = Host.allocated_bytes!({})
	Host.assert!(first.occurrences.len() == 1 and first.occurrences.map(|value| TimedRecurrence.Occurrence.source(TimedOccurrence.start(value))).get(0) == Ok(anchor) and first.steps <= 8 and first.zone_segments <= 8)
	for occurrence in first.occurrences {
		Host.assert!(PosixSpan.coordinate_width(TimedOccurrence.span(occurrence)) == Ok(PosixDelta.from_microseconds(3600000000)))
	}
	resume = match first.status {
		Limited(progress) => progress.cursor
		Complete => crash "unbounded date series stopped at first output"
	}
	before_second = Host.allocated_bytes!({})
	second = match TimedSchedule.collect(resume, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 8, max_zone_candidates: 1 }, max_occurrences: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded resumed date"
	}
	after_second = Host.allocated_bytes!({})
	Host.assert!(second.occurrences.len() == 1 and second.occurrences.map(|value| TimedRecurrence.Occurrence.source(TimedOccurrence.start(value))).get(0) == Ok(ExportFixture.local(2000, 2)) and second.steps <= 8 and second.zone_segments <= 8)
	for occurrence in second.occurrences {
		Host.assert!(PosixSpan.coordinate_width(TimedOccurrence.span(occurrence)) == Ok(PosixDelta.from_microseconds(3600000000)))
	}
	{ bytes: parts.rule.to_utf8(), work: [before_construct - before_input, before_access - before_construct, before_wrapper - before_access, before_export - before_wrapper, after_export - before_export, after_cursor - before_cursor, after_first - after_cursor, after_second - before_second] }
}
