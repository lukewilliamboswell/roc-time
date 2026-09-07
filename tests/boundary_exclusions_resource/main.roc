app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.TimedRecurrence
import time.CalendarPattern
import time.CalendarDate
import time.GregorianDate
import time.LocalDateTime
import BoundaryFixture

# R12/R15: runtime-sized immutable exclusion tables and a Forever horizon.
# Counters measure cumulative requested bytes, not live or retained memory.
# Retain backing slices and declaration views across consumption to expose copies.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "4096") ?? 4096
	ownership = args.get(2) ?? "shared"
	horizon = I64.from_str(args.get(3) ?? "200000") ?? 200000
	ceiling = U64.from_str(args.get(4) ?? "65536") ?? 65536
	Host.assert!(count <= 4096 and horizon > 2000 and horizon <= 200000)
	anchor = BoundaryFixture.label(0)
	date = CalendarDate.as_gregorian(LocalDateTime.date(anchor)) ?? crash "anchor date"
	end_date = GregorianDate.from_fields({ year: horizon, month: 1, day: 1 }) ?? crash "horizon date"
	end = LocalDateTime.new(CalendarDate.from_gregorian(end_date), LocalDateTime.clock(anchor))
	rules = BoundaryFixture.rules({})
	base = TimedRecurrence.new({ date, clock: LocalDateTime.clock(anchor) }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Forever, by_set_pos: [] }) ?? crash "base recurrence"
	before_input = Host.allocated_bytes!({})
	backing = BoundaryFixture.inputs(count + 2)
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
	rule = TimedRecurrence.with_boundary_exclusions(base, inputs) ?? crash "boundary construction"
	after_construct = Host.allocated_bytes!({})
	Host.assert!(after_construct - before_construct <= 65536 + count * 64)
	definition = TimedRecurrence.definition(rule)
	after_access = Host.allocated_bytes!({})
	Host.assert!(after_access == after_construct and definition.boundary_exclusions.len() == count)
	before_cursor = Host.allocated_bytes!({})
	cursor = TimedRecurrence.cursor(rule, { start: anchor, end }, { rules, occurrence: RequireUnique, gap: RejectGap }) ?? crash "boundary cursor"
	after_cursor = Host.allocated_bytes!({})
	first = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "boundary prefix"
	after_first = Host.allocated_bytes!({})
	Host.assert!(first.occurrences.map(TimedRecurrence.Occurrence.source) == [anchor] and first.steps <= 8 and first.zone_segments <= 1)
	resume = match first.status {
		Limited(progress) => progress.cursor
		Complete => crash "Forever prefix falsely complete"
	}
	before_second = Host.allocated_bytes!({})
	second = TimedRecurrence.Cursor.collect(resume, { work: { max_steps: 8, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "boundary resumption"
	after_second = Host.allocated_bytes!({})
	Host.assert!(second.occurrences.map(TimedRecurrence.Occurrence.source) == [BoundaryFixture.label(1)] and second.steps <= 8 and second.zone_segments <= 1)
	Host.assert!(after_cursor - before_cursor <= ceiling and after_first - after_cursor <= ceiling and after_second - before_second <= ceiling)
	match retained {
		Some(original) => Host.assert!(original == BoundaryFixture.inputs(count + 2))
		None => {}
	}
	Host.assert!(definition.boundary_exclusions.len() == count and TimedRecurrence.definition(rule).anchor == anchor)
	{ bytes: "boundary-exclusions".to_utf8(), work: [before_construct - before_input, after_construct - before_construct, after_access - after_construct, after_cursor - before_cursor, after_first - after_cursor, after_second - before_second] }
}
