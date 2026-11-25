import fuzz.Model
import time.Calendar
import time.Coverage
import time.FixedOffset
import time.GregorianDate
import time.PosixBoundary
import time.PosixSpan
import time.Recurrence.AllDay as AllDay
import time.Recurrence.AllDayOccurrence as Occurrence
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Date as DateRecurrence
import time.ZoneRules

## Two daily events straddle a synthetic dateline move at POSIX
## zero. Local January 1 is skipped. January 2 maps to [0, 86400s).
## Each preimage requires two segment visits, including empty segments.
AllDayBudgetModel :: [].{
	Action : [SpendSharedBudget, HoldOutput, ReadOneSegment, Finish]
	Cursor : AllDay(U64)
	Value : Occurrence({ series : U64, date : GregorianDate })
	World : { path : List(Action), cursor : Cursor, saved : Cursor, remaining : U64, finished : Bool, valid : Bool }

	day_us : I64
	day_us = 86400000000

	date : U8 -> GregorianDate
	date = |day| GregorianDate.from_fields({ year: 1970, month: 1, day }) ?? crash "fixture date"

	point = PosixBoundary.from_microseconds

	span = |start, end| PosixSpan.new({ start: point(start), end: point(end) }) ?? crash "fixture span"

	rule : DateRecurrence
	rule = DateRecurrence.new(date(1), { pattern: CalendarPattern.defaults(Daily), termination: Count(2), by_set_pos: [], inclusions: [], exclusions: [] }) ?? crash "fixture rule"

	window : DateRecurrence.Window
	window = { start: date(1), end: date(4) }

	initial : Cursor
	initial = {
		rules = ZoneRules.Provider.new_bounded({
			name: "Synthetic/Dateline",
			version: "one",
			validity: span(-3 * day_us, 5 * day_us),
			initial: FixedOffset.from_seconds(0),
			transitions: [{ at: point(0), offset: FixedOffset.from_seconds(86400) }],
			bounds: { minimum: 0, maximum: 86400 },
		}) ?? crash "fixture zone"
		AllDay.new({ series: 42.U64, rule, window, days: 1, rules }) ?? crash "fixture series"
	}

	work : AllDay.Limits
	work = { max_date_steps: 32, max_date_buffered: 1, max_zone_segments: 2, max_zone_members: 1 }

	identity : Value, U8 -> Bool
	identity = |value, day| Occurrence.id(value) == { series: 42, date: date(day) } and Occurrence.date(value) == Calendar.Date.from_gregorian(date(day)) and Occurrence.days(value) == 1

	first : List(Value) -> Bool
	first = |values| match values {
		[value] => identity(value, 1) and Occurrence.coverage(value) == Coverage.empty
		_ => False
	}

	second : Value -> Bool
	second = |value| identity(value, 2) and Coverage.to_spans(Occurrence.coverage(value)) == [span(0, day_us)]

	at_end : Cursor -> Bool
	at_end = |cursor| match AllDay.next(cursor, { ..work, max_zone_segments: 0 }) {
		Ok(result) => result.zone_segments == 0 and match result.status {
			End => True
			_ => False
		}
		Err(_) => False
	}

	drain : Cursor, U64 -> Bool
	drain = |cursor, segments| match AllDay.collect(cursor, { work: { ..work, max_date_steps: 0, max_zone_segments: segments }, max_occurrences: 1 }) {
		Ok(result) => match (result.status, result.occurrences) {
			(Limited({ reason: OutputLimit, cursor: after }), [value]) =>
				result.date_steps == 0 and result.zone_segments == segments and second(value) and at_end(after)
			_ => False
		}
		Err(_) => False
	}

	actions : World -> List(Action)
	actions = |world| {
		if world.path.is_empty() {
			return [SpendSharedBudget]
		}
		if world.finished or !world.valid {
			return []
		}
		if world.path.len() == 4 {
			[Finish]
		} else {
			[HoldOutput, ReadOneSegment, Finish]
		}
	}

	step : World, Action -> World
	step = |world, action| {
		advanced = { ..world, path: world.path.append(action) }
		invalid = { ..advanced, valid: False }
		match action {
			SpendSharedBudget => match AllDay.collect(world.cursor, { work, max_occurrences: 2 }) {
				Ok(result) => match result.status {
					Limited({ reason: ZoneWorkLimit, cursor }) =>
						{ ..advanced, cursor, saved: cursor, remaining: 2, valid: first(result.occurrences) and result.zone_segments == 2 and result.date_steps <= work.max_date_steps }
					_ => invalid
				}
				Err(_) => invalid
			}
			HoldOutput => match AllDay.collect(world.cursor, { work: { ..work, max_date_steps: 0 }, max_occurrences: 0 }) {
				Ok(result) => match result.status {
					Limited({ reason: OutputLimit, cursor }) =>
						{ ..advanced, cursor, valid: result.occurrences.is_empty() and result.date_steps == 0 and result.zone_segments == 0 }
					_ => invalid
				}
				Err(_) => invalid
			}
			ReadOneSegment => match AllDay.next(world.cursor, { ..work, max_date_steps: 0, max_zone_segments: 1 }) {
				Ok(result) if result.date_steps == 0 and result.zone_segments == 1 => match result.status {
					Limited({ reason: ZoneWorkLimit, cursor }) if world.remaining == 2 =>
						{ ..advanced, cursor, remaining: 1 }
					Item({ occurrence, cursor }) if world.remaining == 1 =>
						{ ..advanced, finished: True, valid: second(occurrence) and at_end(cursor) and drain(world.saved, 2) }
					_ => invalid
				}
				_ => invalid
			}
			Finish => { ..advanced, finished: True, valid: drain(world.cursor, world.remaining) and drain(world.saved, 2) }
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { path: [], cursor: initial, saved: initial, remaining: 0, finished: False, valid: True },
		actions,
		step,
		rules: [
			Model.always("one batch shares work and every resume preserves the pending date", |world| world.valid),
			Model.sometimes_step("a zero-output call preserves a partially interpreted date in both branches", |{ before, action, after }|
				before.remaining == 1 and before.path.last() == Ok(HoldOutput) and action == Finish and after.valid),
			Model.sometimes_step("next can finish the pending event without date work", |{ before, action, after }|
				before.remaining == 1 and action == ReadOneSegment and after.finished and after.valid),
		],
	}

	# One initial collect, up to three pause/read choices, and a final drain.
	expect {
		report = Model.explore(machine, { depth: 6, key: |world| world.path, verify: EveryStep, blame: EveryRule })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}

	# Choose the exact budget to reach the first date through the public date
	# stage. The oracle is that collect must spend from this allowance once.
	# This leaves the date engine free to change how many steps it charges.
	expect {
		dates = DateRecurrence.cursor(rule, window)?
		prefix = dates.next({ max_steps: work.max_date_steps, max_buffered: work.max_date_buffered })?
		match prefix.status {
			Item(item) if item.date == date(1) => {
				budget = { ..work, max_date_steps: prefix.steps, max_zone_segments: 4 }
				result = AllDay.collect(initial, { work: budget, max_occurrences: 2 })?
				match result.status {
					Limited({ reason: DateWorkLimit, cursor }) => {
						resumed = AllDay.next(cursor, work)?
						first(result.occurrences) and result.date_steps == prefix.steps and result.zone_segments == 2 and
							match resumed.status {
								Item(next) => second(next.occurrence) and at_end(next.cursor)
								_ => False
							}
					}
					_ => False
				}
			}
			_ => False
		}
	}
}
