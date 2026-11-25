import fuzz.Model
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules

## R07/R12. A caller pauses a classification, saves progress and retries under
## different work and capacity limits. Matching occurrences and forward gaps
## share the retained budget even when the final resolution is a fold.
ZoneClassificationModel :: [].{
	Cursor : ZoneRules.ClassificationCursor
	Limits : ZoneRules.ClassificationLimits
	Outcome : [Work, Buffer, Fold]
	Observation : { segments : U64, buffered : U64, outcome : Outcome }
	Branch : { next : [Live(Cursor), Done], prefix : U64 }
	Action : [Read(Limits), Save, Restore]
	World : { active : Branch, saved : Branch, valid : Bool }

	point = PosixBoundary.from_microseconds

	offset = FixedOffset.from_seconds

	rules : ZoneRules
	rules = {
		validity = PosixSpan.new({ start: point(-5000000), end: point(5000000) }) ?? crash "validity"
		ZoneRules.Provider.new_bounded({
			name: "Synthetic/FoldAndGaps",
			version: "v1",
			validity,
			initial: offset(2),
			transitions: [
				{ at: point(-500000), offset: offset(0) },
				{ at: point(0), offset: offset(2) },
				{ at: point(250000), offset: offset(-2) },
				{ at: point(500000), offset: offset(2) },
				{ at: point(750000), offset: offset(0) },
			],
			bounds: { minimum: -2, maximum: 2 },
		}) ?? crash "rules"
	}

	local = FixedOffset.project(offset(0), { boundary: point(1000000), calendar: Gregorian }) ?? crash "label"

	initial = { next: Live(ZoneRules.ClassificationCursor.from_local(rules, local) ?? crash "cursor"), prefix: 0.U64 }

	# At civil second 1, the six segments contribute in order: timeline -1,
	# the gap [0, 2), nothing, the gap [-1.5, 2.5), nothing, timeline +1.
	# These counts describe completed prefixes, irrespective of how the caller
	# divides the work. The separate final check observes the contents and order.
	prefixes : List({ prefix : U64, buffered : U64 })
	prefixes = [0, 1, 2, 2, 3, 3, 4].map_with_index(|buffered, prefix| { prefix, buffered })

	predict : U64, Limits -> { prefix : U64, observation : Observation }
	predict = |prefix, limits| {
		buffered = (prefixes.get(prefix) ?? crash "fixture prefix").buffered
		if buffered > limits.max_candidates {
			return { prefix, observation: { segments: 0, buffered, outcome: Buffer } }
		}
		horizon = U64.min(prefix + limits.max_segments, 6)
		fitting = prefixes.keep_if(|part| part.prefix <= horizon and part.buffered <= limits.max_candidates)
		accepted = fitting.last() ?? crash "empty prefix fits"
		blocked = accepted.prefix < horizon
		outcome = if blocked {
			Buffer
		} else if horizon == 6 {
			Fold
		} else {
			Work
		}
		segments = accepted.prefix - prefix + (
			if blocked {
				1
			} else {
				0
			}
		)
		{ prefix: accepted.prefix, observation: { segments, buffered: accepted.buffered, outcome } }
	}

	valid_fold = |value| {
		ZoneRules.Classification.local(value) == local and
			ZoneRules.Provider.definition(ZoneRules.Classification.rules(value)) == ZoneRules.Provider.definition(rules) and
				ZoneRules.Classification.resolution(value) == Fold([point(-1000000), point(1000000)]) and
					ZoneRules.Classification.gap_transitions(value) == [
						{ at: point(0), before: offset(0), after: offset(2) },
						{ at: point(500000), before: offset(-2), after: offset(2) },
					] and
						ZoneRules.Classification.choose(value, { occurrence: RequireUnique, gap: UseOffsetBeforeGap }) == Err(Ambiguous) and
							ZoneRules.Classification.choose(value, { occurrence: MatchingOffset(offset(0)), gap: UseOffsetBeforeGap }) == Ok({ boundary: point(1000000), adjustment: Exact })
	}

	read : Cursor, Limits -> { next : [Live(Cursor), Done], observation : Observation, valid : Bool }
	read = |cursor, limits| {
		batch = ZoneRules.ClassificationCursor.collect(cursor, limits) ?? crash "finite classification failed"
		(next, outcome, valid) = match batch.status {
			Limited({ cursor: rest, reason }) => (
				Live(rest),
				if reason == BufferLimit {
					Buffer
				} else {
					Work
				},
				True,
			)
			Complete(value) => (Done, Fold, valid_fold(value))
		}
		{ next, observation: { segments: batch.segments, buffered: batch.buffered, outcome }, valid }
	}

	reads : List(Action)
	reads = [0, 1, 2, 6].fold(
		[],
		|available, max_segments|
			[0, 1, 2, 3, 4].fold(available, |out, max_candidates| out.append(Read({ max_segments, max_candidates }))),
	)

	actions : World -> List(Action)
	actions = |world| if world.active.prefix == 6 {
		[Restore]
	} else {
		reads.concat([Save, Restore])
	}

	step : World, Action -> World
	step = |world, action| match action {
		Save => { ..world, saved: world.active }
		Restore => { ..world, active: world.saved }
		Read(limits) => match world.active.next {
			Done => { ..world, valid: False }
			Live(cursor) => {
				expected = predict(world.active.prefix, limits)
				actual = read(cursor, limits)
				{ ..world, active: { next: actual.next, prefix: expected.prefix }, valid: actual.valid and actual.observation == expected.observation }
			}
		}
	}

	can_finish = |branch| match branch.next {
		Done => branch.prefix == 6
		Live(cursor) => {
			drained = read(cursor, { max_segments: 6, max_candidates: 4 })
			drained.valid and drained.observation == { segments: 6 - branch.prefix, buffered: 4, outcome: Fold }
		}
	}

	machine : Model.Machine(World, Action)
	machine = {
		init: { active: initial, saved: initial, valid: True },
		actions,
		step,
		rules: [
			Model.always("work, capacity and limit reason agree with the projected prefix", |world| world.valid),
			Model.always("both branches still reach the exact fold with both gap witnesses", |world| can_finish(world.active) and can_finish(world.saved)),
			Model.sometimes_step("shrinking below a retained match and gap stops before another segment", |{ before, action, after: _ }|
				before.active.prefix == 2 and action == Read({ max_segments: 1, max_candidates: 1 })),
			Model.sometimes_step("a full buffer advances past an empty segment but blocks the next gap", |{ before, action, after }|
				before.active.prefix == 2 and action == Read({ max_segments: 2, max_candidates: 2 }) and after.active.prefix == 3),
			Model.sometimes_step("an older mixed-evidence cursor resumes after completion", |{ before, action, after }|
				action == Restore and before.active.prefix == 6 and after.active.prefix == 2),
		],
	}

	expect {
		# Drain both actual branches before deduplicating their abstract prefixes.
		report = Model.explore(machine, { depth: 12, key: |world| (world.active.prefix, world.saved.prefix), verify: EveryStep })
		if report.verdict != Holds(Exhausted) {
			dbg report
		}
		report.verdict == Holds(Exhausted)
	}
}
