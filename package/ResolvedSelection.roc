import SemanticFact
import CalendarDate
import ClockTime
import FixedOffset
import PosixBoundary
import ResolvedBoundary
import PosixSpan
import Coverage
import LocalDateTime
import ZoneRules

## Complete local-selection coverage retaining its exact interpretation inputs.
ResolvedSelection :: {
	start : LocalDateTime,
	end : LocalDateTime,
	rules : ZoneRules,
	coverage : Coverage,
}.{
	resolve : ZoneRules, LocalDateTime, LocalDateTime -> Try(ResolvedSelection, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	resolve = |rules, start, end| {
		coverage = ZoneRules.select(rules, start, end)?
		Ok({ start, end, rules, coverage })
	}

	Batch : {
		segments : U64,
		buffered : U64,
		status : [Complete(ResolvedSelection), Limited({ cursor : ZoneRules.SelectionCursor, reason : [WorkLimit, BufferLimit] })],
	}

	## Continue a validated zone-selection cursor under explicit work/storage
	## limits. Only complete interpretation becomes a snapshot. The cursor
	## retains the exact rules and civil inputs across all resumptions.
	collect : ZoneRules.SelectionCursor, ZoneRules.SelectionLimits -> Try(Batch, [OutOfRange, ..])
	collect = |cursor, limits| {
		batch = ZoneRules.SelectionCursor.collect(cursor, limits)?
		status = match batch.status {
			Limited(progress) => Limited(progress)
			Complete(coverage) => {
				context = ZoneRules.SelectionCursor.context(cursor)
				Complete({ start: context.start, end: context.end, rules: context.rules, coverage })
			}
		}
		Ok({ segments: batch.segments, buffered: batch.buffered, status })
	}

	coverage : ResolvedSelection -> Coverage
	coverage = |snapshot| snapshot.coverage
	start : ResolvedSelection -> LocalDateTime
	start = |snapshot| snapshot.start
	end : ResolvedSelection -> LocalDateTime
	end = |snapshot| snapshot.end
	rules : ResolvedSelection -> ZoneRules
	rules = |snapshot| snapshot.rules

	reresolve : ResolvedSelection, ZoneRules -> Try(ResolvedSelection, [EmptySelection, ReversedSelection, OutsideValidity, OutOfRange, ..])
	reresolve = |snapshot, new_rules| resolve(new_rules, snapshot.start, snapshot.end)

	same_extent : ResolvedSelection, ResolvedSelection -> Bool
	same_extent = |a, b| a.coverage == b.coverage

	## Equality/hashing preserve civil source identity and complete rule evidence.
	## same_extent instead compares only the resulting compatible-axis coverage.
	is_eq : ResolvedSelection, ResolvedSelection -> Bool
	is_eq = |a, b| a.start == b.start and a.end == b.end and a.coverage == b.coverage and ZoneRules.definition(a.rules) == ZoneRules.definition(b.rules)
	to_hash : ResolvedSelection, Hasher -> Hasher
	to_hash = |value, hasher| ZoneRules.definition(value.rules).to_hash(value.coverage.to_hash(value.end.to_hash(value.start.to_hash(hasher))))

	## Complete snapshots expose stored canonical members without reevaluation.
	fact_count : ResolvedSelection -> U64
	fact_count = |snapshot| Coverage.member_count(snapshot.coverage) + 2
	fact_at : ResolvedSelection, U64 -> [End, Item(SemanticFact)]
	fact_at = |snapshot, index| {
		if index == 0 {
			return Item(SemanticFact.new(CivilSelectionDescription({ start: snapshot.start, end: snapshot.end, member_count: Coverage.member_count(snapshot.coverage) })))
		}
		if index == 1 {
			return Item(context_fact(snapshot.rules))
		}
		# Subtract only after the fixed header cases; huge indexes safely End.
		Coverage.fact_at(snapshot.coverage, index - 1)
	}

	## Limited batches explain inputs and work state, not partial coverage.
	batch_fact_count : Batch -> U64
	batch_fact_count = |batch| match batch.status {
		Complete(snapshot) => fact_count(snapshot) + 1
		Limited(_) => 3
	}
	batch_fact_at : Batch, U64 -> [End, Item(SemanticFact)]
	batch_fact_at = |batch, index| {
		if index == 0 {
			status = match batch.status {
				Complete(_) => Complete
				Limited(progress) => Limited(progress.reason)
			}
			return Item(SemanticFact.new(SelectionEvaluation({ status, segments: batch.segments, buffered: batch.buffered })))
		}
		match batch.status {
			Complete(snapshot) => fact_at(snapshot, index - 1)
			Limited(progress) => {
				if index > 2 {
					return End
				}
				context = ZoneRules.SelectionCursor.context(progress.cursor)
				if index == 1 {
					Item(SemanticFact.new(LocalSelectionDescription({ start: context.start, end: context.end })))
				} else {
					Item(context_fact(context.rules))
				}
			}
		}
	}

	to_inspect : ResolvedSelection -> Str
	to_inspect = |snapshot| match fact_at(snapshot, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "Resolved selection always supplies its summary fact"
	}
}

## Independent bounded timeline enumeration for R07 classification.
expect {
	# Three distinct preimages; a one-member buffer must stop and resume
	# without losing the segment that could not be appended.
	span = PosixSpan.new(test_zonerules_point(-10000000), test_zonerules_point(10000000))?
	rules = ZoneRules.new_bounded(
		"Synthetic/Chunked",
		"v1",
		span,
		FixedOffset.from_seconds(4),
		[
			{ at: test_zonerules_point(0), offset: FixedOffset.from_seconds(2) },
			{ at: test_zonerules_point(1000000), offset: FixedOffset.from_seconds(0) },
		],
		{ minimum: 0, maximum: 4 },
	)?
	initial = ZoneRules.selection_cursor(rules, test_zonerules_local_label(2500000)?, test_zonerules_local_label(2750000)?)?
	zero = ZoneRules.SelectionCursor.collect(initial, { max_segments: 0, max_members: 1 })?
	zero_valid = match zero.status {
		Limited(progress) => progress.reason == WorkLimit and zero.segments == 0
		_ => False
	}
	first = ZoneRules.SelectionCursor.collect(initial, { max_segments: 1, max_members: 1 })?
	match first.status {
		Complete(_) => False
		Limited(progress) => {
			blocked = ZoneRules.SelectionCursor.collect(progress.cursor, { max_segments: 1, max_members: 1 })?
			match blocked.status {
				Complete(_) => False
				Limited(retry) => {
					finished = ZoneRules.SelectionCursor.collect(retry.cursor, { max_segments: 2, max_members: 3 })?
					match finished.status {
						Limited(_) => False
						Complete(coverage) => {
							a = PosixSpan.new(test_zonerules_point(-1500000), test_zonerules_point(-1250000))?
							b = PosixSpan.new(test_zonerules_point(500000), test_zonerules_point(750000))?
							c = PosixSpan.new(test_zonerules_point(2500000), test_zonerules_point(2750000))?
							zero_valid and first.segments == 1 and blocked.segments == 1 and
								retry.reason == BufferLimit and finished.segments == 2 and
									coverage == Coverage.from_spans([a, b, c])
						}
					}
				}
			}
		}
	}
}

expect {
	span = PosixSpan.new(test_zonerules_point(-10000000000), test_zonerules_point(10000000000))?
	old_rules = ZoneRules.new_bounded("Synthetic/Changed", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 3600 })?
	# Deliberately reuse the same name/version with different contents:
	# metadata is not a substitute for retaining the actual immutable rules.
	new_rules = ZoneRules.new_bounded("Synthetic/Changed", "v1", span, FixedOffset.from_seconds(3600), [], { minimum: 0, maximum: 3600 })?
	other_version = ZoneRules.new_bounded("Synthetic/Changed", "v2", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 3600 })?
	local = test_zonerules_local_label(0)?
	original = ResolvedBoundary.resolve(old_rules, local, RequireUnique)?
	changed = ResolvedBoundary.reresolve(original, new_rules)?
	equivalent = ResolvedBoundary.reresolve(original, other_version)?
	end = test_zonerules_local_label(1000000)?
	selection = ResolvedSelection.resolve(old_rules, local, end)?
	cursor = ZoneRules.selection_cursor(old_rules, local, end)?
	limited = ResolvedSelection.collect(cursor, { max_segments: 0, max_members: 1 })?
	resumed_valid = match limited.status {
		Complete(_) => False
		Limited(progress) => {
			batch = ResolvedSelection.collect(progress.cursor, { max_segments: 1, max_members: 1 })?
			match batch.status {
				Limited(_) => False
				Complete(snapshot) => ResolvedSelection.same_extent(snapshot, selection) and
					ResolvedSelection.start(snapshot) == local and ResolvedSelection.end(snapshot) == end and
						ZoneRules.offset_at(ResolvedSelection.rules(snapshot), test_zonerules_point(0)) == Ok(FixedOffset.from_seconds(0))
			}
		}
	}
	moved = ResolvedSelection.reresolve(selection, new_rules)?
	same = ResolvedSelection.reresolve(selection, other_version)?
	original_span = PosixSpan.new(test_zonerules_point(0), test_zonerules_point(1000000))?
	moved_span = PosixSpan.new(test_zonerules_point(-3600000000), test_zonerules_point(-3599000000))?
	selection_valid = ResolvedSelection.coverage(selection) == Coverage.from_spans([original_span]) and
		ResolvedSelection.coverage(moved) == Coverage.from_spans([moved_span]) and
			ResolvedSelection.same_extent(selection, same) and !ResolvedSelection.same_extent(selection, moved)
	resumed_valid and selection_valid and ResolvedBoundary.boundary(original) == test_zonerules_point(0) and
		ResolvedBoundary.boundary(changed) == test_zonerules_point(-3600000000) and
			!ResolvedBoundary.same_position(original, changed) and
				ResolvedBoundary.same_position(original, equivalent) and
					ResolvedBoundary.source(changed) == local and
						ResolvedBoundary.offset(original) == FixedOffset.from_seconds(0) and
							ZoneRules.offset_at(ResolvedBoundary.rules(original), test_zonerules_point(0)) == Ok(FixedOffset.from_seconds(0)) and
								ZoneRules.offset_at(ResolvedBoundary.rules(changed), test_zonerules_point(0)) == Ok(FixedOffset.from_seconds(3600))
}

expect {
	# Synthetic dateline move: the whole local epoch day is skipped.
	span = PosixSpan.new(test_zonerules_point(-259200000000), test_zonerules_point(259200000000))?
	rules = ZoneRules.new_bounded(
		"Synthetic/SkippedDay",
		"v1",
		span,
		FixedOffset.from_seconds(0),
		[
			{ at: test_zonerules_point(0), offset: FixedOffset.from_seconds(86400) },
		],
		{ minimum: 0, maximum: 86400 },
	)?
	midnight = ClockTime.from_microseconds_since_midnight(0)?
	first = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
	second = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 2 })?
	third = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 3 })?
	expected = PosixSpan.new(test_zonerules_point(0), test_zonerules_point(86400000000))?
	cursor = ZoneRules.selection_cursor(rules, LocalDateTime.new(first, midnight), LocalDateTime.new(second, midnight))?
	batch = ResolvedSelection.collect(cursor, { max_segments: 2, max_members: 0 })?
	empty_snapshot = match batch.status {
		Limited(_) => False
		Complete(snapshot) => ResolvedSelection.coverage(snapshot) == Coverage.empty and
			ResolvedSelection.start(snapshot) == LocalDateTime.new(first, midnight) and
				ResolvedSelection.end(snapshot) == LocalDateTime.new(second, midnight)
	}
	empty_snapshot and ZoneRules.select(rules, LocalDateTime.new(first, midnight), LocalDateTime.new(second, midnight)) == Ok(Coverage.from_spans([])) and
		ZoneRules.select(rules, LocalDateTime.new(second, midnight), LocalDateTime.new(third, midnight)) == Ok(Coverage.from_spans([expected]))
}

expect {
	span = PosixSpan.new(test_zonerules_point(-10000000), test_zonerules_point(10000000))?
	rules = ZoneRules.new_bounded("Synthetic/Finite", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	start = test_zonerules_local_label(0)?
	end = test_zonerules_local_label(10000000)?
	beyond = test_zonerules_local_label(10000001)?
	expected = PosixSpan.new(test_zonerules_point(0), test_zonerules_point(10000000))?
	# The excluded endpoint may equal validity.end, but never exceed it.
	ZoneRules.select(rules, start, end) == Ok(Coverage.from_spans([expected])) and
		ZoneRules.select(rules, start, beyond) == Err(OutsideValidity)
}

expect {
	span = PosixSpan.new(test_zonerules_point(-10000000), test_zonerules_point(10000000))?
	bad_bounds = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 1, maximum: -1 }) {
		Err(InvalidOffsetBounds) => Bool.True
		_ => Bool.False
	}
	bad_initial = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(3), [], { minimum: -2, maximum: 2 }) {
		Err(OffsetOutsideBounds) => Bool.True
		_ => Bool.False
	}
	bad_transition = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [{ at: test_zonerules_point(0), offset: FixedOffset.from_seconds(-3) }], { minimum: -2, maximum: 2 }) {
		Err(OffsetOutsideBounds) => Bool.True
		_ => Bool.False
	}
	bad_bounds and bad_initial and bad_transition
}

expect {
	var valid = Bool.True
	for first in [-2.I32, 0, 2] {
		for second in [-2.I32, 0, 2] {
			span = PosixSpan.new(test_zonerules_point(-10000000), test_zonerules_point(10000000))?
			rules = ZoneRules.new_bounded(
				"Synthetic/Enumeration",
				"v1",
				span,
				FixedOffset.from_seconds(0),
				[
					{ at: test_zonerules_point(0), offset: FixedOffset.from_seconds(first) },
					{ at: test_zonerules_point(4000000), offset: FixedOffset.from_seconds(second) },
				],
				{ minimum: -2, maximum: 2 },
			)?
			var local_second = -7.I64
			while local_second <= 7 {
				for fraction in [0.I64, 1, 999999] {
					number = local_second * 1000000 + fraction
					local = test_zonerules_local_label(number)?
					var expected = []
					var timeline_second = -10.I64
					while timeline_second < 10 {
						# Direct synthetic fixture definition, independent of
						# transition iteration and inverse offset conversion.
						offset = if timeline_second < 0 {
							0.I32
						} else if timeline_second < 4 {
							first
						} else {
							second
						}
						if timeline_second + offset.to_i64() == local_second {
							expected = expected.append(test_zonerules_point(timeline_second * 1000000 + fraction))
						}
						timeline_second = timeline_second + 1
					}
					classification = match expected {
						[] => Gap
						[only] => Unique(only)
						_ => Fold(expected)
					}
					valid = valid and ZoneRules.resolve(rules, local) == Ok(classification)
				}
				local_second = local_second + 1
			}
			# Even if an in-table match exists, unknown outside rules can
			# supply another candidate. Never claim uniqueness at this edge.
			edge = test_zonerules_local_label(-9000000)?
			valid = valid and ZoneRules.resolve(rules, edge) == Err(OutsideValidity)
		}
	}
	valid
}

expect {
	span = PosixSpan.new(test_zonerules_point(-10000000), test_zonerules_point(10000000))?
	rules = ZoneRules.new_bounded(
		"Synthetic/Triple",
		"v1",
		span,
		FixedOffset.from_seconds(4),
		[
			{ at: test_zonerules_point(0), offset: FixedOffset.from_seconds(2) },
			{ at: test_zonerules_point(1000000), offset: FixedOffset.from_seconds(0) },
		],
		{ minimum: 0, maximum: 4 },
	)?
	local = test_zonerules_local_label(2500000)?
	end = test_zonerules_local_label(2750000)?
	var policies_valid = Bool.True
	if ZoneRules.resolve_occurrence(rules, local, RequireUnique) != Err(Ambiguous) or
		ZoneRules.resolve_occurrence(rules, local, First) != Ok(test_zonerules_point(-1500000)) or
			ZoneRules.resolve_occurrence(rules, local, Last) != Ok(test_zonerules_point(2500000)) or
				ZoneRules.resolve_occurrence(rules, local, MatchingOffset(FixedOffset.from_seconds(2))) != Ok(test_zonerules_point(500000)) or
					ZoneRules.resolve_occurrence(rules, local, MatchingOffset(FixedOffset.from_seconds(1))) != Err(OffsetConflict) {
		policies_valid = Bool.False
	}
	appointment = ZoneRules.appointment(rules, local, First, end, Last)?
	whole = PosixSpan.new(test_zonerules_point(-1500000), test_zonerules_point(2750000))?
	if appointment != whole or
		ZoneRules.appointment(rules, local, Last, end, First) != Err(ReversedBounds) or
			ZoneRules.appointment(rules, local, First, local, First) != Err(EmptySpan) {
		policies_valid = Bool.False
	}
	selected = ZoneRules.select(rules, local, end)?
	a = PosixSpan.new(test_zonerules_point(-1500000), test_zonerules_point(-1250000))?
	b = PosixSpan.new(test_zonerules_point(500000), test_zonerules_point(750000))?
	c = PosixSpan.new(test_zonerules_point(2500000), test_zonerules_point(2750000))?
	policies_valid and ZoneRules.resolve(rules, local) == Ok(Fold([test_zonerules_point(-1500000), test_zonerules_point(500000), test_zonerules_point(2500000)])) and
		selected == Coverage.from_spans([a, b, c]) and
			ZoneRules.select(rules, local, local) == Err(EmptySelection) and
				ZoneRules.select(rules, end, local) == Err(ReversedSelection)
}

test_zonerules_point = |number| PosixBoundary.from_microseconds(number)

# Test labels near epoch are formed directly from calendar fields and clock
# positions; do not use FixedOffset.project as an inverse-resolution oracle.
test_zonerules_local_label = |number| {
	fields = if number < 0 {
		{ year: 1969.I64, month: 12.U8, day: 31.U8 }
	} else {
		{ year: 1970.I64, month: 1.U8, day: 1.U8 }
	}
	date = CalendarDate.from_fields(Gregorian, fields)?
	clock = ClockTime.from_microseconds_since_midnight(
		if number < 0 {
			number + 86400000000
		} else {
			number
		},
	)?
	Ok(LocalDateTime.new(date, clock))
}

context_fact = |rules| SemanticFact.new(Context({ name: ZoneRules.name(rules), version: ZoneRules.version(rules), validity: ZoneRules.validity(rules), provenance: ZoneRules.provenance(rules) }))

expect {
	# Independent three-preimage timeline: local [2.5,2.75) appears in three
	# distinct segments. Limited facts must never pretend to describe coverage.
	point = PosixBoundary.from_microseconds
	validity = PosixSpan.new(point(-10000000), point(10000000))?
	rules = ZoneRules.new_bounded("Synthetic/SelectionFacts", "facts-v1", validity, FixedOffset.from_seconds(4), [{ at: point(0), offset: FixedOffset.from_seconds(2) }, { at: point(1000000), offset: FixedOffset.from_seconds(0) }], { minimum: 0, maximum: 4 })?
	start = test_zonerules_local_label(2500000)?
	end = test_zonerules_local_label(2750000)?
	cursor = ZoneRules.selection_cursor(rules, start, end)?
	zero = ResolvedSelection.collect(cursor, { max_segments: 0, max_members: 1 })?
	blocked = ResolvedSelection.collect(cursor, { max_segments: 3, max_members: 1 })?
	complete = ResolvedSelection.collect(cursor, { max_segments: 3, max_members: 3 })?
	context = SemanticFact.new(Context({ name: "Synthetic/SelectionFacts", version: "facts-v1", validity, provenance: Supplied }))
	limited_valid = ResolvedSelection.batch_fact_count(zero) == 3 and ResolvedSelection.batch_fact_at(zero, 0) == Item(SemanticFact.new(SelectionEvaluation({ status: Limited(WorkLimit), segments: 0, buffered: 0 }))) and ResolvedSelection.batch_fact_at(zero, 1) == Item(SemanticFact.new(LocalSelectionDescription({ start, end }))) and ResolvedSelection.batch_fact_at(zero, 2) == Item(context) and ResolvedSelection.batch_fact_at(zero, 3) == End and ResolvedSelection.batch_fact_at(zero, U64.highest) == End and ResolvedSelection.batch_fact_at(blocked, 0) == Item(SemanticFact.new(SelectionEvaluation({ status: Limited(BufferLimit), segments: 2, buffered: 1 })))
	complete_valid = match complete.status {
		Limited(_) => False
		Complete(snapshot) => {
			middle = PosixSpan.new(point(500000), point(750000))?
			ResolvedSelection.fact_count(snapshot) == 5 and ResolvedSelection.fact_at(snapshot, 0) == Item(SemanticFact.new(CivilSelectionDescription({ start, end, member_count: 3 }))) and ResolvedSelection.fact_at(snapshot, 1) == Item(context) and ResolvedSelection.fact_at(snapshot, 3) == Item(SemanticFact.new(CoverageMember({ index: 1, span: middle }))) and ResolvedSelection.fact_at(snapshot, 5) == End and ResolvedSelection.fact_at(snapshot, U64.highest) == End and ResolvedSelection.batch_fact_count(complete) == 6 and ResolvedSelection.batch_fact_at(complete, 0) == Item(SemanticFact.new(SelectionEvaluation({ status: Complete, segments: 3, buffered: 3 }))) and ResolvedSelection.batch_fact_at(complete, 6) == End and ResolvedSelection.batch_fact_at(complete, U64.highest) == End
		}
	}
	boundary = ResolvedBoundary.resolve(rules, start, Last)?
	boundary_valid = ResolvedBoundary.fact_count(boundary) == 2 and ResolvedBoundary.fact_at(boundary, 0) == Item(SemanticFact.new(CivilBoundaryDescription({ source: start, policy: Last, boundary: point(2500000), offset: FixedOffset.from_seconds(0) }))) and ResolvedBoundary.fact_at(boundary, 1) == Item(context) and ResolvedBoundary.fact_at(boundary, 2) == End and ResolvedBoundary.fact_at(boundary, U64.highest) == End
	limited_valid and complete_valid and boundary_valid
}

expect {
	# A forward gap yields complete empty coverage; its facts differ from a
	# zero-work limited batch despite both reporting zero buffered members.
	point = PosixBoundary.from_microseconds
	validity = PosixSpan.new(point(-10000000), point(10000000))?
	rules = ZoneRules.new_bounded("Synthetic/GapFacts", "facts-v1", validity, FixedOffset.from_seconds(0), [{ at: point(0), offset: FixedOffset.from_seconds(2) }], { minimum: 0, maximum: 2 })?
	start = test_zonerules_local_label(500000)?
	end = test_zonerules_local_label(750000)?
	cursor = ZoneRules.selection_cursor(rules, start, end)?
	complete = ResolvedSelection.collect(cursor, { max_segments: 2, max_members: 0 })?
	match complete.status {
		Limited(_) => False
		Complete(snapshot) => ResolvedSelection.fact_count(snapshot) == 2 and ResolvedSelection.fact_at(snapshot, 0) == Item(SemanticFact.new(CivilSelectionDescription({ start, end, member_count: 0 }))) and ResolvedSelection.fact_at(snapshot, 2) == End and ResolvedSelection.batch_fact_count(complete) == 3 and ResolvedSelection.batch_fact_at(complete, 0) == Item(SemanticFact.new(SelectionEvaluation({ status: Complete, segments: 2, buffered: 0 })))
	}
}
