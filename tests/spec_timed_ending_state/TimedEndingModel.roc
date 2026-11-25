import fuzz.Model
import time.Calendar
import time.ClockTime
import time.FixedOffset
import time.GregorianDate
import time.LocalDateTime
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Timed as TimedRecurrence
import time.ScheduleDefinition.Cursor as ScheduleCursor
import time.ScheduleDefinition.Occurrence as Occurrence
import time.ZoneRules

## One calendar ending is pending while an explicit inclusion
## remains queued. Its next-day 00:30 label either occurs twice or lies in a
## gap. The coordinate tail extends beyond zone validity in both fixtures.
TimedEndingModel :: [].{
	Mode : [FoldEnding, GapEnding]
	Cursor : ScheduleCursor(U64)
	Value : Occurrence({ series : U64, source : LocalDateTime })
	Action : [Open(Mode), HoldOutput, Shrink, KeepCapacity, Finish]
	Phase : [Unopened, Pending({ mode : Mode, cursor : Cursor, saved : Cursor }), Finished]
	World : { path : List(Action), phase : Phase, valid : Bool }

	point = PosixBoundary.from_microseconds
	offset = FixedOffset.from_seconds
	hour = 3600000000.I64
	day = 24 * hour
	start_us = hour // 2 + 123
	second_us = 12 * hour + 456
	tail = 2 * hour + 7

	date = |day_of_month| GregorianDate.from_fields({ year: 1970, month: 1, day: day_of_month }) ?? crash "fixture date"
	clock = |micros| ClockTime.from_microseconds_since_midnight(micros) ?? crash "fixture clock"
	local = |day_of_month, micros| LocalDateTime.new({ date: Calendar.Date.from_gregorian(date(day_of_month)), clock: clock(micros) })

	open : Mode -> Cursor
	open = |mode| {
		(at, after) = if (mode == FoldEnding) (day + hour, -3600.I32) else (day, 3600.I32)
		validity = PosixSpan.new({ start: point(-day), end: point(day + 2 * hour) }) ?? crash "fixture span"
		rules = ZoneRules.Provider.new_bounded({
			name: "Synthetic/Ending",
			version: "one",
			validity,
			initial: offset(0),
			transitions: [{ at: point(at), offset: offset(after) }],
			bounds: { minimum: I32.min(0, after), maximum: I32.max(0, after) },
		}) ?? crash "fixture zone"
		base = TimedRecurrence.new(
			{ date: date(1), clock: clock(start_us) },
			{
				calendar: CalendarPattern.defaults(Daily),
				clocks: { hours: [], minutes: [], seconds: [] },
				termination: Count(1),
				by_set_pos: [],
			},
		) ?? crash "fixture rule"
		rule = TimedRecurrence.with_inclusions(base, [{ date: date(1), clock: clock(second_us) }]) ?? crash "fixture inclusion"
		ScheduleCursor.new({
			series: 42.U64,
			rule,
			window: { start: local(1, start_us), end: local(2, 0) },
			duration: Calendar({ delta: Calendar.Delta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(tail), occurrence: Last, gap: UseOffsetBeforeGap }),
			overrides: [{ source: local(1, second_us), ending: AtBoundary(point(second_us + 5)) }],
			context: { rules, occurrence: RequireUnique, gap: RejectGap },
		}) ?? crash "fixture schedule"
	}

	work : ScheduleCursor.Limits
	work = { max_steps: 64, max_buffered: 4, max_zone_segments: 3, max_zone_candidates: 2 }

	span_matches = |value, source_us, end| {
		source = local(1, source_us)
		span = Occurrence.span(value)
		Occurrence.id(value) == { series: 42, source } and Occurrence.source(value) == source and
			PosixSpan.start(span) == point(source_us) and PosixSpan.end(span) == point(end)
	}

	first_matches : Value, Mode -> Bool
	first_matches = |value, mode| {
		# The later fold occurrence uses offset -1h. The gap adjustment uses
		# offset zero. Both anchors retain the unprojected next-day 00:30.
		(anchor_us, adjustment) = if mode == FoldEnding {
			(day + start_us + hour, Exact)
		} else {
			(day + start_us, BeforeGap({ at: point(day), before: offset(0), after: offset(3600) }))
		}
		expected = { source: local(2, start_us), choice: { boundary: point(anchor_us), adjustment } }
		span_matches(value, start_us, anchor_us + tail) and Occurrence.calendar_anchor(value) == Some(expected)
	}

	next_is_override : Cursor -> Bool
	next_is_override = |cursor| match ScheduleCursor.collect(cursor, { work, max_occurrences: 2 }) {
		Ok(result) => match (result.status, result.occurrences) {
			(Complete, [value]) =>
				span_matches(value, second_us, second_us + 5) and Occurrence.ending(value) == AtBoundary(point(second_us + 5)) and
					Occurrence.calendar_anchor(value) == None
			_ => False
		}
		Err(_) => False
	}

	resume = |cursor, cap| ScheduleCursor.next(cursor, { ..work, max_steps: 0, max_zone_segments: 1, max_zone_candidates: cap })

	saved_finishes : Cursor, Mode -> Bool
	saved_finishes = |cursor, mode| match resume(cursor, 2) {
		Ok(result) if result.steps == 0 and result.zone_segments == 1 => match result.status {
			Item({ occurrence, cursor: rest }) => first_matches(occurrence, mode) and next_is_override(rest)
			_ => False
		}
		_ => False
	}

	actions : World -> List(Action)
	actions = |world| match world.phase {
		Unopened => [Open(FoldEnding), Open(GapEnding)]
		Finished => []
		Pending(_) if !world.valid => []
		Pending(_) if world.path.len() >= 4 => [Finish]
		Pending(_) => [HoldOutput, Shrink, KeepCapacity, Finish]
	}

	step : World, Action -> World
	step = |world, action| {
		advanced = { ..world, path: world.path.append(action) }
		invalid = { ..advanced, valid: False }
		match (action, world.phase) {
			(Open(mode), Unopened) => match ScheduleCursor.next(open(mode), work) {
				Ok(result) if result.zone_segments == 3 and result.end_buffered == 1 => match result.status {
					Limited({ reason: EndZoneWorkLimit, cursor }) => { ..advanced, phase: Pending({ mode, cursor, saved: cursor }) }
					_ => invalid
				}
				_ => invalid
			}
			(HoldOutput, Pending(state)) => match ScheduleCursor.collect(state.cursor, { work, max_occurrences: 0 }) {
				Ok(result) if result.steps == 0 and result.zone_segments == 0 and result.occurrences.is_empty() => match result.status {
					Limited({ reason: OutputLimit, cursor }) => { ..advanced, phase: Pending({ ..state, cursor }) }
					_ => invalid
				}
				_ => invalid
			}
			(_, Pending(state)) => {
				cap = match action {
					Shrink => 0
					KeepCapacity => 1
					_ => 2
				}
				match resume(state.cursor, cap) {
					Ok(result) if result.steps == 0 and result.zone_segments == (if (cap == 0) 0 else 1) => match result.status {
						Limited({ reason: EndZoneBufferLimit, cursor }) if result.end_buffered == 1 and (cap == 0 or (cap == 1 and state.mode == FoldEnding)) =>
							{ ..advanced, phase: Pending({ ..state, cursor }) }
						Item({ occurrence, cursor }) if cap == 2 or (cap == 1 and state.mode == GapEnding) =>
							{ ..advanced, phase: Finished, valid: first_matches(occurrence, state.mode) and next_is_override(cursor) and saved_finishes(state.saved, state.mode) }
						_ => invalid
					}
					_ => invalid
				}
			}
			_ => invalid
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { path: [], phase: Unopened, valid: True },
		actions,
		step,
		rules: [
			Model.always("budgets preserve the pending ending, its anchor, and the queued override", |world| world.valid),
			Model.sometimes_step("a retained fold ends after a shrink and a full-capacity retry", |{ after, .. }|
				after.valid and after.path == [Open(FoldEnding), Shrink, KeepCapacity, Finish]),
			Model.sometimes_step("a saved gap completes at capacity after output was withheld", |{ after, .. }|
				after.valid and after.path == [Open(GapEnding), HoldOutput, KeepCapacity]),
		],
	}

	expect {
		# Keep the short history in the key. Equal public counters alone
		# cannot establish equal candidate buffers or queued starts.
		report = Model.explore(machine, { depth: 6, key: |world| world.path, verify: EveryStep, blame: EveryRule })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}
}
