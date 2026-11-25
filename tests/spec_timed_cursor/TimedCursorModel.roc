import fuzz.Model
import time.Calendar
import time.ClockTime
import time.FixedOffset
import time.GregorianDate
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.Recurrence.CalendarPattern as CalendarPattern
import time.Recurrence.Timed as TimedRecurrence
import time.Recurrence.TimedCursor as TimedCursor
import time.Recurrence.TimedStart as TimedStart
import time.ZoneRules

# The label 1970-01-01 00:00:01 resolves to POSIX second 1
# in the first segment and POSIX second 2 in the next. Classify the same
# folded label as either a rule start or an earlier explicit inclusion.
# Candidate storage and segment work can change independently while the
# classification is pending, without discarding its first retained match.
TimedCursorModel :: [].{
	Origin : [RuleStart, EarlyInclusion]
	Policy : [First, Last, RequireUnique]
	Action : [Open({ origin : Origin, policy : Policy }), FirstSegment, Shrink, NoZoneWork, NoSpareSlot, Resolve]
	Phase : [Unopened, Ready(TimedCursor), Pending({ current : TimedCursor, retained : TimedCursor }), Finished]
	World : { history : List(Action), phase : Phase, policy : Policy, valid : Bool }

	date : GregorianDate
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 }) ?? crash "fixture date"

	clock : U8 -> ClockTime
	clock = |second| ClockTime.from_fields({ hour: 0, minute: 0, second, microsecond: 0 }) ?? crash "fixture clock"

	local : U8 -> LocalDateTime
	local = |second| LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock: clock(second) })

	point : I64 -> PosixBoundary
	point = |second| PosixBoundary.from_microseconds(second * 1000000)

	limits : TimedRecurrence.Limits
	limits = { max_steps: 128, max_buffered: 2, max_zone_segments: 1, max_zone_candidates: 2 }

	open : { origin : Origin, policy : Policy } -> TimedCursor
	open = |{ origin, policy }| {
		# DTSTART at second 3 is on the exclusive window end. In that
		# branch only the second-1 inclusion reaches zone classification.
		start = if origin == RuleStart {
			clock(1)
		} else {
			clock(3)
		}
		base = TimedRecurrence.new(
			{ date, clock: start },
			{ calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] },
		) ?? crash "fixture recurrence"
		rule = if origin == RuleStart {
			base
		} else {
			TimedRecurrence.with_inclusions(base, [{ date, clock: clock(1) }]) ?? crash "fixture inclusion"
		}
		validity = PosixSpan.new({ start: point(-1), end: point(7) }) ?? crash "fixture validity"
		rules = ZoneRules.Provider.new_bounded({
			name: "Synthetic/RecurrenceFold",
			version: "v1",
			validity,
			initial: FixedOffset.from_seconds(0),
			transitions: [{ at: point(2), offset: FixedOffset.from_seconds(-1) }],
			bounds: { minimum: -1, maximum: 0 },
		}) ?? crash "fixture rules"
		occurrence : ZoneRules.OccurrencePolicy
		occurrence = match policy {
			First => First
			Last => Last
			RequireUnique => RequireUnique
		}
		TimedRecurrence.cursor(rule, { window: { start: local(0), end: local(3) }, context: { rules, occurrence, gap: RejectGap } }) ?? crash "fixture window"
	}

	pause : TimedCursor, TimedRecurrence.Limits, TimedRecurrence.Limit, U64 -> [Some(TimedCursor), None]
	pause = |cursor, budget, expected_reason, expected_segments| match TimedCursor.next(cursor, budget) {
		Ok(batch) => match batch.status {
			Limited(progress) if progress.reason == expected_reason and batch.zone_segments == expected_segments and batch.zone_buffered == 1 and batch.steps <= budget.max_steps and batch.buffered <= budget.max_buffered => Some(progress.cursor)
			_ => None
		}
		Err(_) => None
	}

	# The one remaining segment must be sufficient even after repeated
	# pauses. Resolve the active cursor and the retained first snapshot
	# against the same independent, two-element inverse image.
	resolves : TimedCursor, Policy -> Bool
	resolves = |cursor, policy| match TimedCursor.next(cursor, limits) {
		Err(Ambiguous) => policy == RequireUnique
		Err(_) => False
		Ok(batch) => match batch.status {
			Item(item) => {
				selected = if policy == First {
					point(1)
				} else {
					point(2)
				}
				policy != RequireUnique and batch.zone_segments == 1 and batch.zone_buffered == 0 and
					TimedStart.source(item.occurrence) == local(1) and TimedStart.boundary(item.occurrence) == selected and TimedStart.adjustment(item.occurrence) == Exact and
						match TimedCursor.next(item.cursor, { ..limits, max_zone_segments: 0 }) {
							Ok(after) => match after.status {
								End => after.zone_segments == 0
								_ => False
							}
							Err(_) => False
						}
			}
			_ => False
		}
	}

	actions : World -> List(Action)
	actions = |world| match world.phase {
		Unopened => [RuleStart, EarlyInclusion].fold(
			[],
			|acc, origin| acc.concat([First, Last, RequireUnique].map(|policy| Open({ origin, policy }))),
		)
		Ready(_) => [FirstSegment]
		Pending(_) => if world.history.len() < 5 {
			[Shrink, NoZoneWork, NoSpareSlot, Resolve]
		} else {
			[Resolve]
		}
		Finished => []
	}

	step : World, Action -> World
	step = |world, action| {
		advanced = { ..world, history: world.history.append(action) }
		match (world.phase, action) {
			(Unopened, Open(input)) => { ..advanced, policy: input.policy, phase: Ready(open(input)) }
			(Ready(cursor), FirstSegment) => match pause(cursor, limits, ZoneWorkLimit, 1) {
				Some(rest) => { ..advanced, phase: Pending({ current: rest, retained: rest }) }
				None => { ..advanced, valid: False }
			}
			(Pending(branch), Resolve) => { ..advanced, phase: Finished, valid: resolves(branch.current, world.policy) and resolves(branch.retained, world.policy) }
			(Pending(branch), pause_action) => {
				next = match pause_action {
					Shrink => pause(branch.current, { ..limits, max_zone_candidates: 0 }, ZoneBufferLimit, 0)
					NoZoneWork => pause(branch.current, { ..limits, max_zone_segments: 0 }, ZoneWorkLimit, 0)
					NoSpareSlot => pause(branch.current, { ..limits, max_zone_candidates: 1 }, ZoneBufferLimit, 1)
					_ => None
				}
				match next {
					Some(rest) => { ..advanced, phase: Pending({ ..branch, current: rest }) }
					None => { ..advanced, valid: False }
				}
			}
			_ => { ..advanced, valid: False }
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { history: [], phase: Unopened, policy: First, valid: True },
		actions,
		step,
		rules: [
			Model.always("pending zone work and matches survive budget changes", |world| world.valid),
			Model.sometimes_step("the next call can resolve Last after shrinking a retained rule start", |{ before, action, after }| action == Resolve and after.valid and before.history == [Open({ origin: RuleStart, policy: Last }), FirstSegment, Shrink]),
			Model.sometimes_step("an inclusion can resume after changing both capacities", |{ before, action, after }| action == Resolve and after.valid and before.history == [Open({ origin: EarlyInclusion, policy: First }), FirstSegment, NoZoneWork, NoSpareSlot, Shrink]),
			Model.sometimes_step("resuming an inclusion can still report ambiguity", |{ before, action, after }| action == Resolve and after.valid and before.history == [Open({ origin: EarlyInclusion, policy: RequireUnique }), FirstSegment, Shrink]),
		],
	}

	# One opening and one segment, then up to three pauses before resolving.
	# Equal budgets and retained-count observations may hide different cursor
	# states, so the complete bounded history identifies each state.
	# Restarting a pending inclusion on Shrink makes a second Shrink inspect
	# a segment, despite the same retained match still blocking progress.
	expect {
		report = Model.explore(machine, { depth: 7, key: |world| world.history, verify: EveryStep, blame: EveryRule })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}
}
