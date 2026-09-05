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
	transitions : List(Transition),
}.{
	Transition : { at : PosixBoundary, offset : FixedOffset }
	OffsetBounds : { minimum : I32, maximum : I32 }
	Resolution : [Gap, Unique(PosixBoundary), Fold(List(PosixBoundary))]

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
		Ok({ name, version, validity, initial, transitions, bounds })
	}

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
