app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.CalendarPattern
import time.DateRecurrence
import time.GregorianDate
import time.RfcDateRule
import ExportFixture

# R11/R12/R14/R15. Input, native construction, definition access, export and
# first/resumed consumption have separate allocation scopes. Requested bytes
# are allocation traffic, not live or retained memory. Effects observe results.
main! = |args| {
	count = U64.from_str(args.get(1) ?? "4096") ?? 4096
	ownership = args.get(2) ?? "shared"
	horizon = I64.from_str(args.get(3) ?? "2000000000") ?? 2000000000
	ceiling = U64.from_str(args.get(4) ?? "2000000") ?? 2000000
	Host.assert!(count <= 4096 and horizon > 2000 and horizon <= 2000000000)
	anchor = ExportFixture.date(2000, 1)
	end = ExportFixture.date(horizon, 1)
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
	rule = match DateRecurrence.new(anchor, { pattern: { ..CalendarPattern.defaults(Daily), by_month: months }, termination: Forever, by_set_pos: [], inclusions: [], exclusions: [] }) {
		Ok(value) => value
		Err(_) => crash "valid unbounded resource rule"
	}
	before_access = Host.allocated_bytes!({})
	definition = DateRecurrence.definition(rule)
	Host.assert!(definition.anchor == anchor and definition.spec.termination == Forever and definition.spec.pattern.by_month.len() == count)
	retained_definition = if ownership == "owned" {
		None
	} else {
		Some(definition)
	}
	before_export = Host.allocated_bytes!({})
	Host.assert!(before_export == before_access)
	parts = match RfcDateRule.to_parts(rule) {
		Ok(value) => value
		Err(_) => crash "valid DATE export"
	}
	after_export = Host.allocated_bytes!({})
	Host.assert!(after_export - before_export <= ceiling)
	expected = if count == 0 {
		"FREQ=DAILY;INTERVAL=1;WKST=MO"
	} else if count == 1 {
		"FREQ=DAILY;INTERVAL=1;BYMONTH=1;WKST=MO"
	} else {
		"FREQ=DAILY;INTERVAL=1;BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12;WKST=MO"
	}
	Host.assert!(parts.start == "20000101" and parts.rule == expected and parts.inclusions.is_empty() and parts.exclusions.is_empty())
	match retained_definition {
		Some(original) => Host.assert!(original.spec.pattern.by_month == ExportFixture.months(count + 2).sublist({ start: shift, len: count }))
		None => {}
	}
	match retained {
		Some(original) => Host.assert!(original.len() == count + 2 and original.get(0) == Ok(1))
		None => {}
	}
	# The same saved declaration feeds a small window and a billion-year window;
	# both must yield the same first two dates within a small work allowance.
	restored = match RfcDateRule.parse(parts) {
		Ok(value) => value
		Err(_) => crash "resource export cannot be restored"
	}
	before_cursor = Host.allocated_bytes!({})
	cursor = match DateRecurrence.cursor(restored, { start: anchor, end }) {
		Ok(value) => value
		Err(_) => crash "valid resource window"
	}
	after_cursor = Host.allocated_bytes!({})
	first = match DateRecurrence.Cursor.collect(cursor, { max_steps: 8, max_buffered: 1, max_occurrences: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded first date"
	}
	after_first = Host.allocated_bytes!({})
	Host.assert!(first.dates.len() == 1 and first.dates.get(0) == Ok(anchor) and first.steps <= 8 and first.buffered <= 1)
	resume = match first.status {
		Limited(progress) => progress.cursor
		Complete => crash "unbounded date series stopped at first output"
	}
	before_second = Host.allocated_bytes!({})
	second = match DateRecurrence.Cursor.collect(resume, { max_steps: 8, max_buffered: 1, max_occurrences: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded resumed date"
	}
	after_second = Host.allocated_bytes!({})
	Host.assert!(second.dates.len() == 1 and second.dates.get(0) == Ok(ExportFixture.date(2000, 2)) and second.steps <= 8 and second.buffered <= 1)
	{ bytes: parts.rule.to_utf8(), work: [before_construct - before_input, before_access - before_construct, before_export - before_access, after_export - before_export, after_cursor - before_cursor, after_first - after_cursor, after_second - before_second] }
}
