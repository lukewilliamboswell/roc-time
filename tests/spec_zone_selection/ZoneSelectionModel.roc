import fuzz.Model
import time.Calendar
import time.ClockTime
import time.Coverage
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules

## R07/R12. A booking reader expands a local selection through finite zone
## rules. The caller changes limits and can resume an earlier retained branch.
## The reference projects each grid cell forward under its fixture offset,
## then counts connected runs in prefixes of the timeline.
ZoneSelectionModel :: [].{
	Extent : { start : I64, end : I64 }
	Segment : { start : I64, end : I64, offset : I32 }
	Cell : { tick : I64, prefix : U64, label : I64 }
	Limits : ZoneRules.SelectionLimits
	Cursor : ZoneRules.SelectionCursor
	Branch : { next : [Live(Cursor), Done], prefix : U64 }
	Observation : { segments : U64, buffered : U64, outcome : [Work, Buffer, Complete(List(Extent))] }
	Action : [Read(Limits), Save, Restore]
	World : {
		active : Branch,
		saved : Branch,
		observed : [Idle, Batch({ actual : Observation, expected : Observation })],
	}

	# Each tick is half a second. The civil range [0, 4) has timeline runs
	# [-4, -1), [0, 4), [6, 10). The first touches a transition and coalesces,
	# the fourth segment contributes nothing, and the last run ends exactly
	# at the authoritative upper validity bound.
	tick_us : I64
	tick_us = 500000

	timeline : List(Segment)
	timeline = [
		{ start: -8, end: -2, offset: 2 },
		{ start: -2, end: -1, offset: 1 },
		{ start: -1, end: 4, offset: 0 },
		{ start: 4, end: 6, offset: 1 },
		{ start: 6, end: 10, offset: -3 },
	]

	boundary : I64 -> PosixBoundary
	boundary = |tick| PosixBoundary.from_microseconds(tick * tick_us)

	local : I64 -> LocalDateTime
	local = |tick| {
		date = Calendar.Date.from_fields(Gregorian, { year: 1970, month: 1, day: 1 }) ?? crash "fixture date"
		clock = ClockTime.from_microseconds_since_midnight(tick * tick_us) ?? crash "fixture clock"
		LocalDateTime.new({ date, clock })
	}

	labels : { start : LocalDateTime, end : LocalDateTime }
	labels = { start: local(0), end: local(4) }

	rules : ZoneRules
	rules = {
		validity = PosixSpan.new({ start: boundary(-8), end: boundary(10) }) ?? crash "fixture validity"
		ZoneRules.Provider.new_bounded({
			name: "Synthetic/BookingFold",
			version: "one",
			validity,
			initial: FixedOffset.from_seconds(2),
			bounds: { minimum: -3, maximum: 2 },
			transitions: timeline.drop_first(1).map(
				|segment| {
					at: boundary(segment.start),
					offset: FixedOffset.from_seconds(segment.offset),
				},
			),
		}) ?? crash "fixture zone rules"
	}

	grid : List(Cell)
	grid = {
		var $cells = []
		var $prefix = 0.U64
		for segment in timeline {
			$prefix = $prefix + 1
			var $tick = segment.start
			while $tick < segment.end {
				$cells = $cells.append({ tick: $tick, prefix: $prefix, label: $tick + 2 * segment.offset.to_i64() })
				$tick = $tick + 1
			}
		}
		$cells
	}

	prefixes : List(U64)
	prefixes = [0, 1, 2, 3, 4, 5]

	coverage_at : U64 -> List(Extent)
	coverage_at = |prefix| {
		ticks = grid.keep_if(|cell| cell.prefix <= prefix and cell.label >= 0 and cell.label < 4).map(|cell| cell.tick)
		starts = ticks.keep_if(|tick| !ticks.contains(tick - 1))
		ends = ticks.keep_if(|tick| !ticks.contains(tick + 1))
		List.map2(starts, ends, |start, end| { start: start * tick_us, end: (end + 1) * tick_us })
	}

	# Choose the first prefix blocked by capacity within the reachable work
	# horizon. Discovery of a blocked segment costs one work unit. A budget
	# already smaller than the retained prefix prevents any new work.
	predict : U64, Limits -> { prefix : U64, observation : Observation }
	predict = |prefix, { max_segments, max_members }| {
		buffered = coverage_at(prefix).len()
		if buffered > max_members {
			return { prefix, observation: { segments: 0, buffered, outcome: Buffer } }
		}
		horizon = U64.min(timeline.len(), prefix + max_segments)
		blocked = prefixes.find_first(|p| p > prefix and p <= horizon and coverage_at(p).len() > max_members)
		match blocked {
			Ok(p) => {
				prefix: p - 1,
				observation: { segments: p - prefix, buffered: coverage_at(p - 1).len(), outcome: Buffer },
			}
			Err(_) => {
				coverage = coverage_at(horizon)
				outcome = if horizon == timeline.len() {
					Complete(coverage)
				} else {
					Work
				}
				{ prefix: horizon, observation: { segments: horizon - prefix, buffered: coverage.len(), outcome } }
			}
		}
	}

	read : Cursor, Limits -> { next : [Live(Cursor), Done], observation : Observation }
	read = |cursor, limits| {
		batch = ZoneRules.SelectionCursor.collect(cursor, limits) ?? crash "bounded fold fixture collection failed"
		(next, outcome) = match batch.status {
			Limited({ cursor: rest, reason }) => (
				Live(rest),
				if reason == BufferLimit {
					Buffer
				} else {
					Work
				},
			)
			Complete(coverage) => (
				Done,
				Complete(
					Coverage.to_spans(coverage).map(
						|span| {
							start: PosixBoundary.to_microseconds(PosixSpan.start(span)),
							end: PosixBoundary.to_microseconds(PosixSpan.end(span)),
						},
					),
				),
			)
		}
		{ next, observation: { segments: batch.segments, buffered: batch.buffered, outcome } }
	}

	initial : Branch
	initial = {
		next: Live(ZoneRules.SelectionCursor.from_bounds(rules, labels) ?? crash "fold fixture cursor"),
		prefix: 0,
	}

	reads : List(Action)
	reads = [0, 1, 2, 5].fold([], |available, max_segments|
		[0, 1, 2, 3].fold(available, |out, max_members| out.append(Read({ max_segments, max_members }))))

	actions : World -> List(Action)
	actions = |world| if world.active.prefix == timeline.len() {
		[Restore]
	} else {
		reads.concat([Save, Restore])
	}

	step : World, Action -> World
	step = |world, action| match action {
		Save => { ..world, saved: world.active, observed: Idle }
		Restore => { ..world, active: world.saved, observed: Idle }
		Read(limits) => {
			cursor = match world.active.next {
				Live(value) => value
				Done => crash "read after completion"
			}
			predicted = predict(world.active.prefix, limits)
			actual = read(cursor, limits)
			{
				..world,
				active: { next: actual.next, prefix: predicted.prefix },
				observed: Batch({ actual: actual.observation, expected: predicted.observation }),
			}
		}
	}

	# Check both actual continuations before deduplication. The generous drain
	# observes the remaining segment work and final run boundaries. This also
	# checks the value returned when a read hits capacity without advancing.
	can_finish : Branch -> Bool
	can_finish = |branch| match branch.next {
		Done => branch.prefix == timeline.len()
		Live(cursor) => {
			context = ZoneRules.SelectionCursor.context(cursor)
			context.start == labels.start and context.end == labels.end and
				ZoneRules.Provider.definition(context.rules) == ZoneRules.Provider.definition(rules) and
					read(cursor, { max_segments: 5, max_members: 3 }).observation ==
						predict(branch.prefix, { max_segments: 5, max_members: 3 }).observation
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { active: initial, saved: initial, observed: Idle },
		actions,
		step,
		rules: [
			Model.always_step(
				"segment work, buffer size, limit and final spans agree with the timeline prefixes",
				|{ before: _, action: _, after }|
					match after.observed {
						Idle => True
						Batch(batch) => batch.actual == batch.expected
					},
			),
			Model.always("both live branches finish from their own prefix with the original context", |world|
				can_finish(world.active) and can_finish(world.saved)),
			Model.sometimes_step(
				"a smaller cap stops a live buffer before doing any work",
				|{ before, action, after: _ }| match action {
					Read(limits) => coverage_at(before.active.prefix).len() > limits.max_members and limits.max_segments > 0
					_ => False
				},
			),
			Model.sometimes_step("a touching segment merges at capacity", |{ before, action, after }|
				before.active.prefix == 1 and after.active.prefix == 2 and action == Read({ max_segments: 1, max_members: 1 })),
			Model.sometimes_step("an empty segment still costs work before the last fold branch", |{ before, action, after }|
				before.active.prefix == 3 and after.active.prefix == 4 and action == Read({ max_segments: 1, max_members: 2 })),
			Model.sometimes_step("an attempted fold branch costs work and remains pending at capacity", |{ before, action, after }|
				before.active.prefix == 3 and after.active.prefix == 4 and action == Read({ max_segments: 2, max_members: 2 })),
			Model.sometimes_step("an earlier nonempty fork resumes after the active branch finished", |{ before, action, after }|
				action == Restore and before.active.prefix == timeline.len() and after.active.prefix > 0),
		],
	}

	expect {
		report = Model.explore(
			machine,
			{
				depth: 12,
				key: |world| (world.active.prefix, world.saved.prefix),
				verify: EveryStep,
			},
		)
		match report.verdict {
			Holds(Exhausted) => report.unreached.is_empty()
			_ => crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
	}

	# At timeline zero a two-second forward jump skips the entire selection.
	# A cap of zero members suffices once both segments establish an empty preimage.
	expect {
		gap = ZoneRules.Provider.new_bounded({
			name: "Synthetic/BookingGap",
			version: "one",
			validity: PosixSpan.new({ start: boundary(-8), end: boundary(10) })?,
			initial: FixedOffset.from_seconds(0),
			bounds: { minimum: 0, maximum: 2 },
			transitions: [{ at: boundary(0), offset: FixedOffset.from_seconds(2) }],
		})?
		cursor = ZoneRules.SelectionCursor.from_bounds(gap, labels)?
		paused = read(cursor, { max_segments: 0, max_members: 0 })
		match paused.next {
			Live(rest) => paused.observation == { segments: 0, buffered: 0, outcome: Work } and
				read(rest, { max_segments: 2, max_members: 0 }).observation == { segments: 2, buffered: 0, outcome: Complete([]) }
			Done => False
		}
	}
}
