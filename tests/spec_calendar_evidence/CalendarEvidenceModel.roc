import fuzz.Model
import time.Calendar
import time.Evidence.Calendar as CalendarEvidence
import time.Evidence.CalendarQuery as CalendarQuery
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.CalendarDescription.QualifiedValue as QualifiedCalendarValue
import time.ZoneRules

# A caller checks whether an exact instant lies in an unknown
# actual calendar selection, varying the work allowance and retaining a
# partially read query. The alternatives are January 1, 1970 Gregorian
# second cells. A synthetic -2 second change at timeline second 3 repeats
# civil seconds 1 and 2. All inputs stay within a few seconds of the epoch.
CalendarEvidenceModel :: [].{
	Fixture : [FirstHit, BeforeFold, AtFold, LastHit, BeyondCells, Singleton, OutsideValidity]
	Action : [Open(Fixture), Read(U64), Finish]
	Oracle : { remaining : U64, truth : CalendarEvidence.Truth }
	Branch : { oracle : Oracle, cursor : [None, Some(CalendarQuery)] }
	Observation : { examined : U64, status : [Limited, Complete(CalendarEvidence.Truth)] }
	World : {
		history : List(Action),
		current : Branch,
		saved : Branch,
		observed : Observation,
		valid : Bool,
		finished : Bool,
	}

	empty : Branch
	empty = { oracle: { remaining: 0, truth: Impossible }, cursor: None }

	micros : I64 -> PosixBoundary
	micros = |seconds| PosixBoundary.from_microseconds(seconds * 1000000)

	rules : ZoneRules
	rules = {
		validity = PosixSpan.new({ start: micros(-1), end: micros(7) }) ?? crash "valid fixture interval"
		ZoneRules.Provider.new_bounded({
			name: "Synthetic/EvidenceFold",
			version: "1",
			validity,
			initial: FixedOffset.from_seconds(0),
			transitions: [{ at: micros(3), offset: FixedOffset.from_seconds(-2) }],
			bounds: { minimum: -2, maximum: 0 },
		}) ?? crash "valid fixture rules"
	}

	cell : U8 -> Calendar.Value
	cell = |second| {
		date = Calendar.Date.from_fields(Gregorian, { year: 1970, month: 1, day: 1 }) ?? crash "invalid fixture date"
		Calendar.Value.second(date, { hour: 0, minute: 0, second }) ?? crash "invalid fixture cell"
	}

	fixture_point : Fixture -> I64
	fixture_point = |fixture| match fixture {
		FirstHit | Singleton => 0
		BeforeFold => 1
		AtFold => 3
		LastHit => 5
		BeyondCells => 6
		OutsideValidity => 7
	}

	# Compute the whole membership vector by arithmetic on integer seconds.
	# For mixed evidence, the later of the first two opposing witnesses is
	# the earliest conclusive prefix. For unanimous evidence it is the full
	# vector. A remaining count models work without duplicating the cursor's
	# incremental accumulation of its position and witness flags.
	oracle : List(U8), I64 -> Oracle
	oracle = |cells, timeline| {
		local = if timeline < 3 {
			timeline
		} else {
			timeline - 2
		}
		starts = cells.map(U8.to_i64)
		inside = |start| start <= local and local < start + 1
		# The consecutive cells start at zero, so a cell start also gives its index.
		yes = starts.keep_if(inside).first()
		no = starts.keep_if(|start| !inside(start)).first()
		match (yes, no) {
			(Ok(first_yes), Ok(first_no)) => { remaining: I64.max(first_yes, first_no).to_u64_wrap() + 1, truth: Possible }
			(Ok(_), Err(_)) => { remaining: cells.len(), truth: Definite }
			_ => { remaining: cells.len(), truth: Impossible }
		}
	}

	open : Fixture -> { branch : Branch, valid : Bool }
	open = |fixture| {
		cells = if fixture == Singleton {
			[0]
		} else {
			[0, 1, 2, 3]
		}
		supplied = if fixture == Singleton {
			[0, 0]
		} else {
			[3, 2, 1, 0, 1]
		}
		description = QualifiedCalendarValue.new(cell(0), [{ scope: Second, qualifier: Uncertain }]) ?? crash "valid fixture qualification"
		# Supply reversed and repeated cells. The oracle uses unique ascending
		# cells, the documented order after public construction.
		evidence = CalendarEvidence.new(description, supplied.map(cell)) ?? crash "valid fixture evidence"
		timeline = fixture_point(fixture)
		match CalendarEvidence.query(evidence, { rules, point: micros(timeline) }) {
			Ok(cursor) => {
				branch: { cursor: Some(cursor), oracle: oracle(cells, timeline) },
				valid: fixture != OutsideValidity,
			}
			Err(OutsideValidity) => { branch: empty, valid: fixture == OutsideValidity }
			Err(OutOfRange) => { branch: empty, valid: False }
		}
	}

	read : Branch, U64 -> { branch : Branch, observed : Observation, valid : Bool }
	read = |branch, budget| {
		cursor = match branch.cursor {
			Some(value) => value
			None => crash "read outside live fixture query"
		}
		batch = CalendarQuery.collect(cursor, { max_alternatives: budget })
		(next, status) = match batch.status {
			Limited(remaining) => (Some(remaining), Limited)
			Complete(truth) => (None, Complete(truth))
		}
		examined = U64.min(budget, branch.oracle.remaining)
		remaining = branch.oracle.remaining - examined
		expected = if remaining == 0 {
			Complete(branch.oracle.truth)
		} else {
			Limited
		}
		{
			branch: { cursor: next, oracle: { ..branch.oracle, remaining } },
			observed: { examined: batch.examined, status },
			valid: batch.examined == examined and status == expected,
		}
	}

	drains : Branch -> Bool
	drains = |branch| match branch.cursor {
		None => branch.oracle.remaining == 0
		Some(_) => read(branch, 4).valid
	}

	actions : World -> List(Action)
	actions = |world| {
		if world.history.is_empty() {
			return [FirstHit, BeforeFold, AtFold, LastHit, BeyondCells, Singleton, OutsideValidity].map(|fixture| Open(fixture))
		}
		if world.finished {
			return []
		}
		match world.current.cursor {
			Some(_) => if world.history.len() <= 3 {
				reads = [Read(0), Read(1), Read(2), Read(4)]
				if world.history.len() == 1 {
					reads
				} else {
					reads.append(Finish)
				}
			} else {
				[Finish]
			}
			None => [Finish]
		}
	}

	step : World, Action -> World
	step = |world, action| {
		advanced = { ..world, history: world.history.append(action) }
		match action {
			Open(fixture) => {
				started = open(fixture)
				{ ..advanced, current: started.branch, valid: started.valid }
			}
			Read(budget) => {
				result = read(world.current, budget)
				saved = if world.history.len() == 1 {
					result.branch
				} else {
					world.saved
				}
				{ ..advanced, current: result.branch, saved, observed: result.observed, valid: result.valid }
			}
			Finish => { ..advanced, valid: drains(world.current) and drains(world.saved), finished: True }
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { history: [], current: empty, saved: empty, observed: { examined: 0, status: Limited }, valid: True, finished: False },
		actions,
		step,
		rules: [
			Model.always("status and examined counts agree with the independent decision prefix", |world| world.valid),
			Model.at_rest("both retained branches can finish", |world| world.finished),
			Model.sometimes_step("a zero-budget read yields without work", |{ action, after, before: _ }| action == Read(0) and after.observed == { examined: 0, status: Limited }),
			Model.sometimes_step("a hit followed by a miss stops before the end", |{ before, action, after }| before.history == [Open(FirstHit)] and action == Read(4) and after.observed == { examined: 2, status: Complete(Possible) }),
			Model.sometimes_step("the same mixed result is found at the repeated civil second", |{ before, action, after }| before.history == [Open(AtFold)] and action == Read(4) and after.observed == { examined: 2, status: Complete(Possible) }),
			Model.sometimes_step("an inclusive lower endpoint can be the last witness", |{ before, action, after }| before.history == [Open(LastHit)] and action == Read(4) and after.observed == { examined: 4, status: Complete(Possible) }),
			Model.sometimes_step("an exclusive upper endpoint needs every miss", |{ before, action, after }| before.history == [Open(BeyondCells)] and action == Read(4) and after.observed == { examined: 4, status: Complete(Impossible) }),
			Model.sometimes_step("the singleton needs one affirmative witness", |{ before, action, after }| before.history == [Open(Singleton)] and action == Read(1) and after.observed == { examined: 1, status: Complete(Definite) }),
			Model.sometimes_step("a retained partial query finishes after the active query advances", |{ before, action, after }| action == Finish and after.valid and before.history.get(1) == Ok(Read(1)) and before.saved.oracle.remaining > before.current.oracle.remaining and before.current.oracle.remaining > 0),
			Model.sometimes_step("the zone validity end rejects the point", |{ action, after, before: _ }| action == Open(OutsideValidity) and after.valid),
		],
	}

	# Bound the action grammar to one opening, up to three reads with changing
	# budgets, and a final drain of both branches. Use the full history as
	# key because equal remaining counts do not establish equal cursor state.
	# Requiring full traversal returns Limited at [Open(FirstHit), Read(2)]
	# even though the first two cells already establish Possible.
	expect {
		report = Model.explore(machine, { depth: 6, key: |world| world.history, verify: EveryStep, blame: EveryRule })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}
}
