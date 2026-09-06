import Coverage
import FixedOffset
import LocalDateTime
import PosixBoundary
import PosixSpan

## Immutable finite rules supplied by the caller; no registry or host lookup.
##
## Example
##
## Supply rules explicitly: use `from_database` with the optional zone-data
## package, or construct a bounded snapshot for an application's own clock schedule.
## Offsets are local minus timeline in seconds. A rules snapshot only interprets
## labels inside its declared validity; it never falls back to the machine's zone.
##
## For an ambiguous label, `RequireUnique` returns an error; `First`, `Last`, or
## `MatchingOffset` select an occurrence. `classification_cursor` separates bounded
## interpretation from choosing a result. `select` instead finds all coverage of a
## local-label range, which may be disconnected.
##
## ```roc
## import time.ZoneRules
## import time.FixedOffset
## import time.PosixSpan
## import time.PosixBoundary
## import time.GregorianDate
## import time.CalendarDate
## import time.ClockTime
## import time.LocalDateTime
##
## expect {
##     validity = PosixSpan.from_seconds(-86400, 86400, RejectSubmicrosecond)?
##     rules = ZoneRules.new_bounded(
##         "UTC", "fixed", validity,
##         FixedOffset.from_seconds(0), [],
##         { minimum: 0, maximum: 0 },
##     )?
##     date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
##     clock = ClockTime.from_microseconds_since_midnight(0)?
##     local = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
##     resolved = ZoneRules.resolve_occurrence(rules, local, RequireUnique)
##     resolved == Ok(PosixBoundary.from_microseconds(0))
## }
## ```
##
## When a batch returns `Limited`, process its partial output and resume the returned
## cursor with sufficient budgets. Increasing only the output cap does not fix a
## work or buffer limit.
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

	## Semantic transport, not the opaque record representation or a codec.
	## Boundaries and transition positions retain exact POSIX microseconds;
	## offsets/bounds retain whole seconds. Provenance is preserved in full.
	Definition : { name : Str, version : Str, validity : PosixSpan, initial : FixedOffset, bounds : OffsetBounds, provenance : Provenance, transitions : List(Transition) }
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
		var $previous = PosixSpan.start(validity)
		for transition in transitions {
			if FixedOffset.to_seconds(transition.offset) < bounds.minimum or FixedOffset.to_seconds(transition.offset) > bounds.maximum {
				return Err(OffsetOutsideBounds)
			}
			if transition.at <= PosixSpan.start(validity) or transition.at >= PosixSpan.end(validity) {
				return Err(TransitionOutsideValidity)
			}
			if transition.at <= $previous {
				return Err(UnorderedTransitions)
			}
			$previous = transition.at
		}
		Ok({ name, version, validity, initial, transitions, bounds, provenance: Supplied })
	}

	## Constant-time projection. Transition/string storage may remain shared;
	## names and version labels are not substitutes for the returned actual data.
	definition : ZoneRules -> Definition
	definition = |rules| {
		name: rules.name,
		version: rules.version,
		validity: rules.validity,
		initial: rules.initial,
		bounds: rules.bounds,
		provenance: rules.provenance,
		transitions: rules.transitions,
	}

	## Revalidate transported semantics using the same constructor invariants.
	## O(n) transition work without copying the table. No provider lookup occurs.
	## DatabaseSource retains the second-alignment invariant of from_database;
	## Supplied rules retain the full microsecond domain. Provenance is asserted
	## transport metadata, not authentication of an external database or digest.
	from_definition : Definition -> Try(ZoneRules, [EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, MissingProvenance, ProvenanceNameMismatch, InvalidDatabaseAlignment, ..])
	from_definition = |data| {
		rules = new_bounded(data.name, data.version, data.validity, data.initial, data.transitions, data.bounds)?
		match data.provenance {
			Supplied => {}
			DatabaseSource(source) => {
				if source.requested_name.is_empty() or source.canonical_name.is_empty() or source.source_digest.is_empty() or source.profile.is_empty() {
					return Err(MissingProvenance)
				}
				if source.canonical_name != data.name {
					return Err(ProvenanceNameMismatch)
				}
				if I64.rem_by(PosixBoundary.to_microseconds(PosixSpan.start(data.validity)), 1000000) != 0 or
					I64.rem_by(PosixBoundary.to_microseconds(PosixSpan.end(data.validity)), 1000000) != 0 {
					return Err(InvalidDatabaseAlignment)
				}
				for transition in data.transitions {
					if I64.rem_by(PosixBoundary.to_microseconds(transition.at), 1000000) != 0 {
						return Err(InvalidDatabaseAlignment)
					}
				}
			}
		}
		Ok({ ..rules, provenance: data.provenance })
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
		var $transitions = []
		for entry in data.transitions {
			at = database_boundary(entry.second)?
			$transitions = $transitions.append({ at, offset: FixedOffset.from_seconds(entry.offset) })
		}
		rules = new_bounded(data.canonical_name, data.source_version, validity, FixedOffset.from_seconds(data.initial_offset), $transitions, { minimum: data.minimum_offset, maximum: data.maximum_offset })?
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

	## Authoritative global offset bounds supplied at construction, not merely
	## the extrema observed inside this finite transition table.
	offset_bounds : ZoneRules -> OffsetBounds
	offset_bounds = |rules| rules.bounds

	## A transition's new offset applies at its exact boundary.
	offset_at : ZoneRules, PosixBoundary -> Try(FixedOffset, [OutsideValidity, ..])
	offset_at = |rules, boundary| {
		if boundary < PosixSpan.start(rules.validity) or boundary >= PosixSpan.end(rules.validity) {
			return Err(OutsideValidity)
		}
		var $offset = rules.initial
		for transition in rules.transitions {
			if boundary < transition.at {
				return Ok($offset)
			}
			$offset = transition.offset
		}
		Ok($offset)
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
	BoundaryChoice : { boundary : PosixBoundary, adjustment : [Exact, BeforeGap(GapTransition)] }
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

		## Apply explicit policies to complete evidence, without rescanning rules.
		## First/last/gap choice is constant work; matching an asserted offset is
		## O(log n) in fold occurrences. Gap adjustment retains its transition.
		## MatchingOffset checks the pre-gap offset for an explicit gap adjustment.
		choose : Classification, { occurrence : OccurrencePolicy, gap : [RejectGap, UseOffsetBeforeGap] } -> Try(BoundaryChoice, [Gap, Ambiguous, AmbiguousGap, OffsetConflict, OutOfRange, ..])
		choose = |value, policy| {
			match value.resolution {
				Gap => {
					if policy.gap == RejectGap {
						return Err(Gap)
					}
					transition = match value.gaps {
						[only] => only
						[] => crash "Complete gap classification crosses a forward transition"
						_ => return Err(AmbiguousGap)
					}
					match policy.occurrence {
						MatchingOffset(expected) => if expected != transition.before {
							return Err(OffsetConflict)
						}
						_ => {}
					}
					boundary = FixedOffset.resolve(transition.before, value.local)?
					Ok({ boundary, adjustment: BeforeGap(transition) })
				}
				Unique(boundary) => {
					match policy.occurrence {
						MatchingOffset(expected) => if FixedOffset.resolve(expected, value.local) != Ok(boundary) {
							return Err(OffsetConflict)
						}
						_ => {}
					}
					Ok({ boundary, adjustment: Exact })
				}
				Fold(boundaries) => {
					boundary = match policy.occurrence {
						RequireUnique => return Err(Ambiguous)
						First => classification_boundary_at(boundaries, 0)
						Last => classification_boundary_at(boundaries, boundaries.len() - 1)
						MatchingOffset(expected) => {
							candidate = match FixedOffset.resolve(expected, value.local) {
								Ok(found) => found
								Err(_) => return Err(OffsetConflict)
							}
							var $lower = 0.U64
							var $upper = boundaries.len()
							while $lower < $upper {
								middle = $lower + U64.div_trunc_by($upper - $lower, 2)
								if classification_boundary_at(boundaries, middle) < candidate {
									$lower = middle + 1
								} else {
									$upper = middle
								}
							}
							if $lower == boundaries.len() or classification_boundary_at(boundaries, $lower) != candidate {
								return Err(OffsetConflict)
							}
							candidate
						}
					}
					Ok({ boundary, adjustment: Exact })
				}
			}
		}
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
			# Keep output buffers independently owned during the loop. Rebuilding
			# a whole cursor on each append retains an alias to its old buffer.
			rules = initial.rules
			local = initial.local
			var $index = initial.index
			var $lower = initial.lower
			var $offset = initial.offset
			var $matches = initial.matches
			var $gaps = initial.gaps
			var $done = initial.done
			var $segments = 0.U64
			while True {
				buffered = $matches.len() + $gaps.len()
				if buffered > limits.max_candidates {
					return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, local, index: $index, lower: $lower, offset: $offset, matches: $matches, gaps: $gaps, done: $done }, reason: BufferLimit }) })
				}
				if $done {
					resolution = match $matches {
						[] => Gap
						[only] => Unique(only)
						_ => Fold($matches)
					}
					return Ok({ segments: $segments, buffered, status: Complete({ rules, local, resolution, gaps: $gaps }) })
				}
				if $segments == limits.max_segments {
					return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, local, index: $index, lower: $lower, offset: $offset, matches: $matches, gaps: $gaps, done: $done }, reason: WorkLimit }) })
				}
				transition = rules.transitions.get($index)
				upper = match transition {
					Ok(entry) => entry.at
					Err(_) => PosixSpan.end(rules.validity)
				}
				candidate = FixedOffset.resolve($offset, local)?
				matched = candidate >= $lower and candidate < upper
				gap = match transition {
					Ok(entry) => candidate >= upper and FixedOffset.resolve(entry.offset, local)? < upper
					Err(_) => Bool.False
				}
				$segments = $segments + 1
				if (matched or gap) and buffered == limits.max_candidates {
					return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, local, index: $index, lower: $lower, offset: $offset, matches: $matches, gaps: $gaps, done: $done }, reason: BufferLimit }) })
				}
				if matched {
					$matches = $matches.append(candidate)
				}
				match transition {
					Ok(entry) => {
						if gap {
							$gaps = $gaps.append({ at: upper, before: $offset, after: entry.offset })
						}
						$index = $index + 1
						$lower = upper
						$offset = entry.offset
					}
					Err(_) => {
						$done = True
					}
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
		cursor = classification_cursor(rules, local)?
		batch = ClassificationCursor.collect(cursor, { max_segments: U64.highest, max_candidates: U64.highest })?
		value = match batch.status {
			Complete(result) => result
			Limited(_) => crash "Finite zone classification exhausted U64"
		}
		match Classification.choose(value, { occurrence: policy, gap: RejectGap }) {
			Ok(choice) => Ok(choice.boundary)
			Err(AmbiguousGap) => crash "RejectGap does not choose gap transitions"
			Err(Gap) => Err(Gap)
			Err(Ambiguous) => Err(Ambiguous)
			Err(OffsetConflict) => Err(OffsetConflict)
			Err(OutOfRange) => Err(OutOfRange)
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
			rules = initial.rules
			start = initial.start
			end = initial.end
			var $index = initial.index
			var $lower = initial.lower
			var $offset = initial.offset
			var $builder = initial.builder
			var $done = initial.done
			var $segments = 0.U64
			while True {
				buffered = Coverage.SortedBuilder.member_count($builder)
				if buffered > limits.max_members {
					return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, start, end, index: $index, lower: $lower, offset: $offset, builder: $builder, done: $done }, reason: BufferLimit }) })
				}
				if $done {
					return Ok({ segments: $segments, buffered, status: Complete(Coverage.SortedBuilder.to_coverage($builder)) })
				}
				if $segments == limits.max_segments {
					return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, start, end, index: $index, lower: $lower, offset: $offset, builder: $builder, done: $done }, reason: WorkLimit }) })
				}
				transition = List.get(rules.transitions, $index)
				upper = match transition {
					Ok(entry) => entry.at
					Err(_) => PosixSpan.end(rules.validity)
				}
				span = selected_span($lower, upper, $offset, start, end)?
				$segments = $segments + 1
				match span {
					None => {}
					Some(selected) => {
						# The full result returns the unchanged builder, avoiding an
						# alias retained solely for reconstructing a limited cursor.
						appended = match Coverage.SortedBuilder.append_retaining($builder, selected, limits.max_members) {
							Ok(result) => result
							Err(_) => crash "Zone segments preserve output start order"
						}
						match appended {
							Full(original) => return Ok({ segments: $segments, buffered, status: Limited({ cursor: { rules, start, end, index: $index, lower: $lower, offset: $offset, builder: original, done: $done }, reason: BufferLimit }) })
							Added(updated) => {
								$builder = updated
							}
						}
					}
				}
				match transition {
					Ok(entry) => {
						$index = $index + 1
						$lower = upper
						$offset = entry.offset
					}
					Err(_) => {
						$done = True
					}
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
		var $valid = Bool.True
		for (number, expected) in [(-3.I64, 0.I32), (-2, 0), (-1, 0), (0, 1800), (1, 1800), (2, 0), (3, 0)] {
			$valid = $valid and offset_at(rules, PosixBoundary.from_microseconds(number)) == Ok(FixedOffset.from_seconds(expected))
		}
		$valid and offset_at(rules, PosixBoundary.from_microseconds(-4)) == Err(OutsideValidity) and
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
			# Keep the input cursor shared across continuation. Its original gap
			# witness and blocked segment remain intact after the other branch.
			retained = ZoneRules.ClassificationCursor.collect(progress.cursor, { max_segments: 0, max_candidates: 2 })?
			retained_valid = match retained.status {
				Limited(stopped) => retained.buffered == 1 and retained.segments == 0 and stopped.reason == WorkLimit
				_ => False
			}
			match finished.status {
				Limited(_) => False
				Complete(value) => retained_valid and zero_valid and progress.reason == BufferLimit and limited.segments == 3 and finished.segments == 2 and
					ZoneRules.Classification.resolution(value) == Gap and ZoneRules.Classification.local(value) == local and
						ZoneRules.Classification.choose(value, { occurrence: First, gap: UseOffsetBeforeGap }) == Err(AmbiguousGap) and
							ZoneRules.Classification.gap_transitions(value) == [
								{ at: point(0), before: FixedOffset.from_seconds(0), after: FixedOffset.from_seconds(2) },
								{ at: point(200000), before: FixedOffset.from_seconds(-2), after: FixedOffset.from_seconds(2) },
							]
			}
		}
	}
}

classification_boundary_at = |boundaries, index| match List.get(boundaries, index) {
	Ok(value) => value
	Err(_) => crash "Classification match index invariant"
}

expect {
	point = PosixBoundary.from_microseconds
	validity = PosixSpan.new(point(-10000000), point(10000000))?
	local = FixedOffset.project(FixedOffset.from_seconds(0), point(1000000), Gregorian)?
	var $valid = Bool.True
	for (before, after) in [(0.I32, 2.I32), (2, 0)] {
		rules = ZoneRules.new_bounded("Synthetic/Choice", "v1", validity, FixedOffset.from_seconds(before), [{ at: point(0), offset: FixedOffset.from_seconds(after) }], { minimum: 0, maximum: 2 })?
		cursor = ZoneRules.classification_cursor(rules, local)?
		batch = ZoneRules.ClassificationCursor.collect(cursor, { max_segments: 2, max_candidates: 2 })?
		value = match batch.status {
			Complete(found) => found
			Limited(_) => crash "fixture classification incomplete"
		}
		if before == 0 {
			choice = ZoneRules.Classification.choose(value, { occurrence: First, gap: UseOffsetBeforeGap })?
			$valid = $valid and choice == { boundary: point(1000000), adjustment: BeforeGap({ at: point(0), before: FixedOffset.from_seconds(0), after: FixedOffset.from_seconds(2) }) } and
				ZoneRules.Classification.choose(value, { occurrence: First, gap: RejectGap }) == Err(Gap) and
					ZoneRules.Classification.choose(value, { occurrence: MatchingOffset(FixedOffset.from_seconds(2)), gap: UseOffsetBeforeGap }) == Err(OffsetConflict)
		} else {
			$valid = $valid and ZoneRules.Classification.choose(value, { occurrence: First, gap: RejectGap }) == Ok({ boundary: point(-1000000), adjustment: Exact }) and
				ZoneRules.Classification.choose(value, { occurrence: Last, gap: RejectGap }) == Ok({ boundary: point(1000000), adjustment: Exact }) and
					ZoneRules.Classification.choose(value, { occurrence: MatchingOffset(FixedOffset.from_seconds(0)), gap: RejectGap }) == Ok({ boundary: point(1000000), adjustment: Exact }) and
						ZoneRules.Classification.choose(value, { occurrence: MatchingOffset(FixedOffset.from_seconds(1)), gap: RejectGap }) == Err(OffsetConflict)
		}
	}
	$valid
}

expect {
	# The transport must not round a synthetic subsecond transition or infer
	# authoritative bounds merely from the offsets present in this table.
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(2))?
	original = ZoneRules.new_bounded("Synthetic/Microseconds", "reused-v1", validity, FixedOffset.from_seconds(-1), [{ at: PosixBoundary.from_microseconds(1), offset: FixedOffset.from_seconds(1) }], { minimum: -10, maximum: 10 })?
	transport = ZoneRules.definition(original)
	restored = ZoneRules.from_definition(transport)?
	ZoneRules.definition(restored) == transport and
		ZoneRules.offset_at(restored, PosixBoundary.from_microseconds(0)) == Ok(FixedOffset.from_seconds(-1)) and
			ZoneRules.offset_at(restored, PosixBoundary.from_microseconds(1)) == Ok(FixedOffset.from_seconds(1))
}
expect {
	# Reused labels do not identify actual data. Both immutable tables survive.
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-10), PosixBoundary.from_microseconds(10))?
	first = ZoneRules.new_bounded("Synthetic/Reused", "same-v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 3600 })?
	first_data = ZoneRules.definition(first)
	second = ZoneRules.from_definition({ ..first_data, transitions: [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(3600) }] })?
	ZoneRules.name(first) == ZoneRules.name(second) and ZoneRules.version(first) == ZoneRules.version(second) and
		ZoneRules.definition(first) != ZoneRules.definition(second) and
			ZoneRules.offset_at(first, PosixBoundary.from_microseconds(0)) == Ok(FixedOffset.from_seconds(0)) and
				ZoneRules.offset_at(second, PosixBoundary.from_microseconds(0)) == Ok(FixedOffset.from_seconds(3600))
}
expect {
	original = ZoneRules.from_database(test_zonedatabase_fixture({}))?
	definition = ZoneRules.definition(original)
	restored = ZoneRules.from_definition(definition)?
	ZoneRules.definition(restored) == definition and ZoneRules.provenance(restored) == ZoneRules.provenance(original)
}
expect {
	rules = ZoneRules.from_database(test_zonedatabase_fixture({}))?
	data = ZoneRules.definition(rules)
	provenance = { requested_name: "Synthetic/Alias", canonical_name: "Synthetic/Canonical", source_digest: "fixture-digest", profile: "fixture-profile" }
	definition_status({ ..data, provenance: DatabaseSource({ ..provenance, requested_name: "" }) }) == Err(MissingProvenance) and
		definition_status({ ..data, provenance: DatabaseSource({ ..provenance, canonical_name: "" }) }) == Err(MissingProvenance) and
			definition_status({ ..data, provenance: DatabaseSource({ ..provenance, source_digest: "" }) }) == Err(MissingProvenance) and
				definition_status({ ..data, provenance: DatabaseSource({ ..provenance, profile: "" }) }) == Err(MissingProvenance) and
					definition_status({ ..data, provenance: DatabaseSource({ ..provenance, canonical_name: "Unrelated/Name" }) }) == Err(ProvenanceNameMismatch) and
						definition_status({ ..data, transitions: [{ at: PosixBoundary.from_microseconds(1), offset: FixedOffset.from_seconds(0) }] }) == Err(InvalidDatabaseAlignment) and
							definition_status({ ..data, validity: PosixSpan.new(PosixBoundary.from_microseconds(-9999999), PosixBoundary.from_microseconds(10000000))? }) == Err(InvalidDatabaseAlignment)
}
expect {
	rules = ZoneRules.from_database(test_zonedatabase_fixture({}))?
	data = ZoneRules.definition(rules)
	transition = { at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(0) }
	definition_status({ ..data, name: "" }) == Err(EmptyName) and
		definition_status({ ..data, version: "" }) == Err(EmptyVersion) and
			definition_status({ ..data, bounds: { minimum: 1, maximum: 0 } }) == Err(InvalidOffsetBounds) and
				definition_status({ ..data, initial: FixedOffset.from_seconds(1801) }) == Err(OffsetOutsideBounds) and
					definition_status({ ..data, transitions: [transition, transition] }) == Err(UnorderedTransitions) and
						definition_status({ ..data, transitions: [{ ..transition, at: PosixSpan.start(data.validity) }] }) == Err(TransitionOutsideValidity)
}

definition_status = |data| match ZoneRules.from_definition(data) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
