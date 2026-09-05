import Coverage
import FixedOffset
import LocalDateTime
import PosixBoundary
import PosixSpan

## Immutable finite rules supplied by the caller; no registry or host lookup.
ZoneRules :: {
	name : Str,
	version : Str,
	validity : PosixSpan,
	initial : FixedOffset,
	bounds : OffsetBounds,
	provenance : Provenance,
	transitions : List(Transition),
}.{
	Database : {
		schema : U16,
		axis : Str,
		requested_name : Str,
		canonical_name : Str,
		source_version : Str,
		source_digest : Str,
		profile : Str,
		future_handling : Str,
		start_second : I64,
		end_second : I64,
		initial_offset : I32,
		minimum_offset : I32,
		maximum_offset : I32,
		transitions : List({ second : I64, offset : I32 }),
	}
	Provenance : [Supplied, DatabaseSource({ requested_name : Str, canonical_name : Str, source_digest : Str, profile : Str })]
	Transition : { at : PosixBoundary, offset : FixedOffset }
	OffsetBounds : { minimum : I32, maximum : I32 }
	Resolution : [Gap, Unique(PosixBoundary), Fold(List(PosixBoundary))]
	OccurrencePolicy : [RequireUnique, First, Last, MatchingOffset(FixedOffset)]

	new : Str, Str, PosixSpan, FixedOffset, List(Transition) -> Try(ZoneRules, [EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, ..])
	new = |name, version, validity, initial, transitions| new_bounded(name, version, validity, initial, transitions, { minimum: I32.lowest, maximum: I32.highest })

	## Bounds are a provider guarantee, including outside this finite table.
	## Never infer global bounds merely from the offsets observed in the table.
	new_bounded : Str, Str, PosixSpan, FixedOffset, List(Transition), OffsetBounds -> Try(ZoneRules, [EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, ..])
	new_bounded = |name, version, validity, initial, transitions, bounds| {
		if bounds.minimum > bounds.maximum {
			return Err(InvalidOffsetBounds)
		}
		if FixedOffset.to_seconds(initial) < bounds.minimum or FixedOffset.to_seconds(initial) > bounds.maximum {
			return Err(OffsetOutsideBounds)
		}
		if name.is_empty() {
			return Err(EmptyName)
		}
		if version.is_empty() {
			return Err(EmptyVersion)
		}
		var previous = PosixSpan.start(validity)
		for transition in transitions {
			if FixedOffset.to_seconds(transition.offset) < bounds.minimum or FixedOffset.to_seconds(transition.offset) > bounds.maximum {
				return Err(OffsetOutsideBounds)
			}
			if transition.at <= PosixSpan.start(validity) or transition.at >= PosixSpan.end(validity) {
				return Err(TransitionOutsideValidity)
			}
			if transition.at <= previous {
				return Err(UnorderedTransitions)
			}
			previous = transition.at
		}
		Ok({ name, version, validity, initial, transitions, bounds, provenance: Supplied })
	}

	## Versioned structural data: no nominal dependency on the supplying package.
	from_database : Database -> Try(ZoneRules, [UnsupportedSchema(U16), UnsupportedAxis(Str), UnsupportedFutureHandling(Str), MissingProvenance, EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, EmptySpan, ReversedBounds, OutOfRange, ..])
	from_database = |data| {
		if data.schema != 1 {
			return Err(UnsupportedSchema(data.schema))
		}
		if data.axis != "posix-seconds-1970" {
			return Err(UnsupportedAxis(data.axis))
		}
		if data.future_handling != "expanded-through-validity" {
			return Err(UnsupportedFutureHandling(data.future_handling))
		}
		if data.requested_name.is_empty() or data.source_digest.is_empty() or data.profile.is_empty() {
			return Err(MissingProvenance)
		}
		lower = database_boundary(data.start_second)?
		upper = database_boundary(data.end_second)?
		validity = PosixSpan.new(lower, upper)?
		var transitions = []
		for entry in data.transitions {
			at = database_boundary(entry.second)?
			transitions = transitions.append({ at, offset: FixedOffset.from_seconds(entry.offset) })
		}
		rules = new_bounded(data.canonical_name, data.source_version, validity, FixedOffset.from_seconds(data.initial_offset), transitions, { minimum: data.minimum_offset, maximum: data.maximum_offset })?
		Ok({ ..rules, provenance: DatabaseSource({ requested_name: data.requested_name, canonical_name: data.canonical_name, source_digest: data.source_digest, profile: data.profile }) })
	}

	provenance : ZoneRules -> Provenance
	provenance = |rules| rules.provenance

	name : ZoneRules -> Str
	name = |rules| rules.name
	version : ZoneRules -> Str
	version = |rules| rules.version
	validity : ZoneRules -> PosixSpan
	validity = |rules| rules.validity

	## A transition's new offset applies at its exact boundary.
	offset_at : ZoneRules, PosixBoundary -> Try(FixedOffset, [OutsideValidity, ..])
	offset_at = |rules, boundary| {
		if boundary < PosixSpan.start(rules.validity) or boundary >= PosixSpan.end(rules.validity) {
			return Err(OutsideValidity)
		}
		var offset = rules.initial
		for transition in rules.transitions {
			if boundary < transition.at {
				return Ok(offset)
			}
			offset = transition.offset
		}
		Ok(offset)
	}

	## Complete classification only when every possible candidate is covered.
	resolve : ZoneRules, LocalDateTime -> Try(Resolution, [OutsideValidity, OutOfRange, ..])
	resolve = |rules, local| {
		cursor = classification_cursor(rules, local)?
		batch = ClassificationCursor.collect(cursor, { max_segments: U64.highest, max_candidates: U64.highest })?
		match batch.status {
			Complete(value) => Ok(Classification.resolution(value))
			Limited(_) => crash "Finite allocated zone table exhausted U64 limits"
		}
	}

	GapTransition : { at : PosixBoundary, before : FixedOffset, after : FixedOffset }
	Classification :: { rules : ZoneRules, local : LocalDateTime, resolution : Resolution, gaps : List(GapTransition) }.{
		resolution : Classification -> Resolution
		resolution = |value| value.resolution
		rules : Classification -> ZoneRules
		rules = |value| value.rules
		local : Classification -> LocalDateTime
		local = |value| value.local

		## Forward transitions whose skipped local interval contains the label.
		## A synthetic table can contain several; never silently select one.
		gap_transitions : Classification -> List(GapTransition)
		gap_transitions = |value| value.gaps
		to_inspect : Classification -> Str
		to_inspect = |value| {
			kind = match value.resolution {
				Gap => "Gap"
				Unique(_) => "Unique"
				Fold(matches) => "Fold(${matches.len().to_str()})"
			}
			"ZoneRules.Classification(${kind}, ${Str.inspect(value.local)}, gap_transitions=${value.gaps.len().to_str()})"
		}
	}
	ClassificationLimits : { max_segments : U64, max_candidates : U64 }
	ClassificationBatch : {
		segments : U64,
		buffered : U64,
		status : [Complete(Classification), Limited({ cursor : ClassificationCursor, reason : [WorkLimit, BufferLimit] })],
	}
	classification_cursor : ZoneRules, LocalDateTime -> Try(ClassificationCursor, [OutsideValidity, OutOfRange, ..])
	classification_cursor = |rules, local| {
		earliest = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.maximum), local)?
		latest = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.minimum), local)?
		if earliest < PosixSpan.start(rules.validity) or latest >= PosixSpan.end(rules.validity) {
			return Err(OutsideValidity)
		}
		Ok({ rules, local, index: 0, lower: PosixSpan.start(rules.validity), offset: rules.initial, matches: [], gaps: [], done: Bool.False })
	}
	ClassificationCursor :: {
		rules : ZoneRules,
		local : LocalDateTime,
		index : U64,
		lower : PosixBoundary,
		offset : FixedOffset,
		matches : List(PosixBoundary),
		gaps : List(GapTransition),
		done : Bool,
	}.{

		## One work unit visits one constant-offset segment and its ending
		## transition. Capacity includes matches and forward-gap evidence.
		## Shared cursor snapshots may copy retained buffers on append.
		collect : ClassificationCursor, ClassificationLimits -> Try(ClassificationBatch, [OutOfRange, ..])
		collect = |initial, limits| {
			var state = initial
			var segments = 0.U64
			while True {
				buffered = state.matches.len() + state.gaps.len()
				if buffered > limits.max_candidates {
					return Ok({ segments, buffered, status: Limited({ cursor: state, reason: BufferLimit }) })
				}
				if state.done {
					resolution = match state.matches {
						[] => Gap
						[only] => Unique(only)
						_ => Fold(state.matches)
					}
					return Ok({ segments, buffered, status: Complete({ rules: state.rules, local: state.local, resolution, gaps: state.gaps }) })
				}
				if segments == limits.max_segments {
					return Ok({ segments, buffered, status: Limited({ cursor: state, reason: WorkLimit }) })
				}
				transition = state.rules.transitions.get(state.index)
				upper = match transition {
					Ok(value) => value.at
					Err(_) => PosixSpan.end(state.rules.validity)
				}
				candidate = FixedOffset.resolve(state.offset, state.local)?
				matches = candidate >= state.lower and candidate < upper
				gap = match transition {
					Ok(value) => candidate >= upper and FixedOffset.resolve(value.offset, state.local)? < upper
					Err(_) => Bool.False
				}
				segments = segments + 1
				if (matches or gap) and buffered == limits.max_candidates {
					return Ok({ segments, buffered, status: Limited({ cursor: state, reason: BufferLimit }) })
				}
				if matches {
					state = { ..state, matches: state.matches.append(candidate) }
				}
				state = match transition {
					Ok(value) => {
						gaps = if gap {
							state.gaps.append({ at: upper, before: state.offset, after: value.offset })
						} else {
							state.gaps
						}
						{ ..state, gaps, index: state.index + 1, lower: upper, offset: value.offset }
					}
					Err(_) => { ..state, done: Bool.True }
				}
			}
			crash "Classification loop returns an outcome"
		}
		to_inspect : ClassificationCursor -> Str
		to_inspect = |state| "ZoneRules.ClassificationCursor(segment=${state.index.to_str()}, buffered=${(state.matches.len() + state.gaps.len()).to_str()})"
	}

	## Choose explicitly; gaps never silently move to another local label.
	resolve_occurrence : ZoneRules, LocalDateTime, OccurrencePolicy -> Try(PosixBoundary, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, ..])
	resolve_occurrence = |rules, local, policy| {
		classification = resolve(rules, local)?
		match classification {
			Gap => Err(Gap)
			Unique(boundary) => match policy {
				MatchingOffset(expected) => if offset_at(rules, boundary)? == expected {
					Ok(boundary)
				} else {
					Err(OffsetConflict)
				}
				_ => Ok(boundary)
			}
			Fold(boundaries) => match policy {
				RequireUnique => Err(Ambiguous)
				First => match List.get(boundaries, 0) {
					Ok(boundary) => Ok(boundary)
					Err(_) => crash "internal nonempty fold invariant"
				}
				Last => match List.get(boundaries, List.len(boundaries) - 1) {
					Ok(boundary) => Ok(boundary)
					Err(_) => crash "internal nonempty fold invariant"
				}
				MatchingOffset(expected) => {
					candidate = match FixedOffset.resolve(expected, local) {
						Ok(value) => value
						Err(_) => return Err(OffsetConflict)
					}
					for boundary in boundaries {
						if boundary == candidate {
							return Ok(boundary)
						}
					}
					Err(OffsetConflict)
				}
			}
		}
	}

	## Appointment between independently chosen occurrences, not a selection.
	appointment : ZoneRules, LocalDateTime, OccurrencePolicy, LocalDateTime, OccurrencePolicy -> Try(PosixSpan, [Gap, Ambiguous, OffsetConflict, OutsideValidity, OutOfRange, EmptySpan, ReversedBounds, ..])
	appointment = |rules, start, start_policy, end, end_policy| {
		lower = resolve_occurrence(rules, start, start_policy)?
		upper = resolve_occurrence(rules, end, end_policy)?
		PosixSpan.new(lower, upper)
	}

	## Preimage of the half-open local selection; never an endpoint hull.
	select : ZoneRules, LocalDateTime, LocalDateTime -> Try(Coverage, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	select = |rules, start, end| {
		cursor = selection_cursor(rules, start, end)?
		batch = SelectionCursor.collect(cursor, { max_segments: U64.highest, max_members: U64.highest })?
		match batch.status {
			Complete(coverage) => Ok(coverage)
			Limited(_) => crash "Finite allocated zone table exhausted U64 limits"
		}
	}

	SelectionLimits : { max_segments : U64, max_members : U64 }
	SelectionBatch : {
		segments : U64,
		buffered : U64,
		status : [Complete(Coverage), Limited({ cursor : SelectionCursor, reason : [WorkLimit, BufferLimit] })],
	}

	## Prove the full inverse range is covered before any segment is evaluated.
	## The opaque cursor binds the immutable rules and original local selection.
	selection_cursor : ZoneRules, LocalDateTime, LocalDateTime -> Try(SelectionCursor, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	selection_cursor = |rules, start, end| {
		match LocalDateTime.compare_position(start, end) {
			EQ => return Err(EmptySelection)
			GT => return Err(ReversedSelection)
			LT => {}
		}
		earliest = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.maximum), start)?
		latest_end = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.minimum), end)?
		# End is excluded: equality with the upper validity boundary is safe.
		if earliest < PosixSpan.start(rules.validity) or latest_end > PosixSpan.end(rules.validity) {
			return Err(OutsideValidity)
		}
		Ok({ rules, start, end, index: 0, lower: PosixSpan.start(rules.validity), offset: rules.initial, builder: Coverage.SortedBuilder.empty, done: Bool.False })
	}

	SelectionCursor :: {
		rules : ZoneRules,
		start : LocalDateTime,
		end : LocalDateTime,
		index : U64,
		lower : PosixBoundary,
		offset : FixedOffset,
		builder : Coverage.SortedBuilder,
		done : Bool,
	}.{
		context : SelectionCursor -> { rules : ZoneRules, start : LocalDateTime, end : LocalDateTime }
		context = |cursor| { rules: cursor.rules, start: cursor.start, end: cursor.end }

		## One segment unit performs fixed offset arithmetic and one ordered
		## builder append. Rejected/empty segments still consume work. Shared
		## output appends can copy up to max_members retained spans. Zero budgets
		## return Limited; no incomplete coverage is exposed as a complete value.
		collect : SelectionCursor, SelectionLimits -> Try(SelectionBatch, [OutOfRange, ..])
		collect = |initial, limits| {
			var cursor = initial
			var segments = 0.U64
			while True {
				buffered = Coverage.SortedBuilder.member_count(cursor.builder)
				if buffered > limits.max_members {
					return Ok({ segments, buffered, status: Limited({ cursor, reason: BufferLimit }) })
				}
				if cursor.done {
					return Ok({ segments, buffered, status: Complete(Coverage.SortedBuilder.to_coverage(cursor.builder)) })
				}
				if segments == limits.max_segments {
					return Ok({ segments, buffered, status: Limited({ cursor, reason: WorkLimit }) })
				}
				transition = List.get(cursor.rules.transitions, cursor.index)
				upper = match transition {
					Ok(value) => value.at
					Err(_) => PosixSpan.end(cursor.rules.validity)
				}
				span = selected_span(cursor.lower, upper, cursor.offset, cursor.start, cursor.end)?
				segments = segments + 1
				match span {
					None => {}
					Some(value) => {
						appended = match Coverage.SortedBuilder.append_bounded(cursor.builder, value, limits.max_members) {
							Ok(result) => result
							Err(_) => crash "Zone segments preserve output start order"
						}
						match appended {
							Full => return Ok({ segments, buffered, status: Limited({ cursor, reason: BufferLimit }) })
							Added(builder) => {
								cursor = { ..cursor, builder }
							}
						}
					}
				}
				cursor = match transition {
					Ok(value) => { ..cursor, index: cursor.index + 1, lower: upper, offset: value.offset }
					Err(_) => { ..cursor, done: Bool.True }
				}
			}
			crash "Selection loop returns a batch"
		}
		to_inspect : SelectionCursor -> Str
		to_inspect = |cursor| "ZoneRules.SelectionCursor(segment=${cursor.index.to_str()}, members=${Coverage.SortedBuilder.member_count(cursor.builder).to_str()})"
	}

	expect {
		# Synthetic rule fixture: timeline cells, independently enumerated.
		# Whole-second offsets need not imply whole-second transition positions.
		span = PosixSpan.new(PosixBoundary.from_microseconds(-3), PosixBoundary.from_microseconds(4))?
		initial = FixedOffset.from_seconds(0)
		changed = FixedOffset.from_seconds(1800)
		rules = new(
			"Synthetic/HalfHour",
			"fixture-v1",
			span,
			initial,
			[
				{ at: PosixBoundary.from_microseconds(0), offset: changed },
				{ at: PosixBoundary.from_microseconds(2), offset: initial },
			],
		)?
		var valid = Bool.True
		for (number, expected) in [(-3.I64, 0.I32), (-2, 0), (-1, 0), (0, 1800), (1, 1800), (2, 0), (3, 0)] {
			valid = valid and offset_at(rules, PosixBoundary.from_microseconds(number)) == Ok(FixedOffset.from_seconds(expected))
		}
		valid and offset_at(rules, PosixBoundary.from_microseconds(-4)) == Err(OutsideValidity) and
			offset_at(rules, PosixBoundary.from_microseconds(4)) == Err(OutsideValidity)
	}

	expect {
		span = PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(10))?
		offset = FixedOffset.from_seconds(0)
		transition = { at: PosixBoundary.from_microseconds(5), offset }
		# Check errors by matching so ZoneRules need not define semantic equality.
		duplicate = match new("Synthetic", "v1", span, offset, [transition, transition]) {
			Err(UnorderedTransitions) => Bool.True
			_ => Bool.False
		}
		outside = match new("Synthetic", "v1", span, offset, [{ at: PosixBoundary.from_microseconds(10), offset }]) {
			Err(TransitionOutsideValidity) => Bool.True
			_ => Bool.False
		}
		duplicate and outside
	}
}

selected_span = |lower, upper, offset, start, end| {
	candidate_start = FixedOffset.resolve(offset, start)?
	candidate_end = FixedOffset.resolve(offset, end)?
	clipped_start = if candidate_start > lower {
		candidate_start
	} else {
		lower
	}
	clipped_end = if candidate_end < upper {
		candidate_end
	} else {
		upper
	}
	if clipped_start < clipped_end {
		# Strict comparison establishes the constructor's nonempty invariant.
		span = match PosixSpan.new(clipped_start, clipped_end) {
			Ok(value) => value
			Err(_) => crash "internal clipped zone span invariant"
		}
		Ok(Some(span))
	} else {
		Ok(None)
	}
}

# Source units are seconds; do not narrow before scaling or wrap at I64 limits.
database_boundary : I64 -> Try(PosixBoundary, [OutOfRange, ..])
database_boundary = |seconds| match I128.to_i64_try(seconds.to_i128() * 1000000) {
	Ok(micros) => Ok(PosixBoundary.from_microseconds(micros))
	Err(_) => Err(OutOfRange)
}

expect {
	rules = ZoneRules.from_database(test_zonedatabase_fixture({}))?
	ZoneRules.name(rules) == "Synthetic/Canonical" and
		ZoneRules.version(rules) == "source-v1" and
			ZoneRules.offset_at(rules, PosixBoundary.from_microseconds(-1)) == Ok(FixedOffset.from_seconds(0)) and
				ZoneRules.offset_at(rules, PosixBoundary.from_microseconds(0)) == Ok(FixedOffset.from_seconds(1800)) and
					ZoneRules.provenance(rules) == DatabaseSource({ requested_name: "Synthetic/Alias", canonical_name: "Synthetic/Canonical", source_digest: "test_zonedatabase_fixture-content-v1", profile: "synthetic-bounded" })
}

expect {
	good = test_zonedatabase_fixture({})
	test_zonedatabase_status({ ..good, schema: 2 }) == Err(UnsupportedSchema(2)) and
		test_zonedatabase_status({ ..good, axis: "tai-seconds" }) == Err(UnsupportedAxis("tai-seconds")) and
			test_zonedatabase_status({ ..good, future_handling: "last-offset-forever" }) == Err(UnsupportedFutureHandling("last-offset-forever")) and
				test_zonedatabase_status({ ..good, source_digest: "" }) == Err(MissingProvenance) and
					test_zonedatabase_status({ ..good, end_second: I64.highest }) == Err(OutOfRange) and
						test_zonedatabase_status({ ..good, start_second: 10, end_second: -10 }) == Err(ReversedBounds) and
							test_zonedatabase_status({ ..good, minimum_offset: 1 }) == Err(OffsetOutsideBounds) and
								test_zonedatabase_status({ ..good, transitions: [{ second: 10, offset: 0 }] }) == Err(TransitionOutsideValidity)
}

test_zonedatabase_fixture : {} -> ZoneRules.Database
test_zonedatabase_fixture = |_| {
	schema: 1,
	axis: "posix-seconds-1970",
	requested_name: "Synthetic/Alias",
	canonical_name: "Synthetic/Canonical",
	source_version: "source-v1",
	source_digest: "test_zonedatabase_fixture-content-v1",
	profile: "synthetic-bounded",
	future_handling: "expanded-through-validity",
	start_second: -10,
	end_second: 10,
	initial_offset: 0,
	minimum_offset: 0,
	maximum_offset: 1800,
	transitions: [{ second: 0, offset: 1800 }],
}

test_zonedatabase_status = |data| match ZoneRules.from_database(data) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

# Two forward jumps can skip the same label in a synthetic rule table.
# Preserve both transition witnesses; a future adapter must not guess which
# pre-gap offset it should use. Buffer exhaustion must preserve the next jump.
expect {
	point = PosixBoundary.from_microseconds
	validity = PosixSpan.new(point(-10000000), point(10000000))?
	rules = ZoneRules.new_bounded(
		"Synthetic/RepeatedGap",
		"v1",
		validity,
		FixedOffset.from_seconds(0),
		[
			{ at: point(0), offset: FixedOffset.from_seconds(2) },
			{ at: point(100000), offset: FixedOffset.from_seconds(-2) },
			{ at: point(200000), offset: FixedOffset.from_seconds(2) },
		],
		{ minimum: -2, maximum: 2 },
	)?
	local = FixedOffset.project(FixedOffset.from_seconds(0), point(1000000), Gregorian)?
	initial = ZoneRules.classification_cursor(rules, local)?
	zero = ZoneRules.ClassificationCursor.collect(initial, { max_segments: 0, max_candidates: 2 })?
	zero_valid = match zero.status {
		Limited(progress) => zero.segments == 0 and progress.reason == WorkLimit
		_ => False
	}
	limited = ZoneRules.ClassificationCursor.collect(initial, { max_segments: 4, max_candidates: 1 })?
	match limited.status {
		Complete(_) => False
		Limited(progress) => {
			finished = ZoneRules.ClassificationCursor.collect(progress.cursor, { max_segments: 2, max_candidates: 2 })?
			match finished.status {
				Limited(_) => False
				Complete(value) => zero_valid and progress.reason == BufferLimit and limited.segments == 3 and finished.segments == 2 and
					ZoneRules.Classification.resolution(value) == Gap and ZoneRules.Classification.local(value) == local and
						ZoneRules.Classification.gap_transitions(value) == [
							{ at: point(0), before: FixedOffset.from_seconds(0), after: FixedOffset.from_seconds(2) },
							{ at: point(200000), before: FixedOffset.from_seconds(-2), after: FixedOffset.from_seconds(2) },
						]
			}
		}
	}
}
