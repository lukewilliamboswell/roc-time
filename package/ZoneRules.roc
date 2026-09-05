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
		earliest = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.maximum), local)?
		latest = FixedOffset.resolve(FixedOffset.from_seconds(rules.bounds.minimum), local)?
		if earliest < PosixSpan.start(rules.validity) or latest >= PosixSpan.end(rules.validity) {
			return Err(OutsideValidity)
		}
		var matches = []
		var lower = PosixSpan.start(rules.validity)
		var offset = rules.initial
		for transition in rules.transitions {
			candidate = FixedOffset.resolve(offset, local)?
			if candidate >= lower and candidate < transition.at {
				matches = matches.append(candidate)
			}
			lower = transition.at
			offset = transition.offset
		}
		candidate = FixedOffset.resolve(offset, local)?
		if candidate >= lower and candidate < PosixSpan.end(rules.validity) {
			matches = matches.append(candidate)
		}
		# Segments are ordered and disjoint; matches are sorted and unique.
		Ok(
			match matches {
				[] => Gap
				[only] => Unique(only)
				_ => Fold(matches)
			},
		)
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
		var spans = []
		var lower = PosixSpan.start(rules.validity)
		var offset = rules.initial
		for transition in rules.transitions {
			spans = append_selected(spans, lower, transition.at, offset, start, end)?
			lower = transition.at
			offset = transition.offset
		}
		spans = append_selected(spans, lower, PosixSpan.end(rules.validity), offset, start, end)?
		# Each span is clipped to an ordered disjoint timeline segment.
		# Sorted construction merges touch without sorting or filling gaps.
		match Coverage.from_sorted_spans(spans) {
			Ok(coverage) => Ok(coverage)
			Err(_) => crash "internal zone segment ordering invariant"
		}
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

append_selected = |spans, lower, upper, offset, start, end| {
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
		Ok(spans.append(span))
	} else {
		Ok(spans)
	}
}

# Source units are seconds; do not narrow before scaling or wrap at I64 limits.
database_boundary : I64 -> Try(PosixBoundary, [OutOfRange, ..])
database_boundary = |seconds| match I128.to_i64_try(seconds.to_i128() * 1000000) {
	Ok(micros) => Ok(PosixBoundary.from_microseconds(micros))
	Err(_) => Err(OutOfRange)
}
