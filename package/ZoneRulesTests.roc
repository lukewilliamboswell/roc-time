import CalendarDate
import ClockTime
import Coverage
import FixedOffset
import LocalDateTime
import PosixBoundary
import ResolvedBoundary
import ResolvedSelection
import PosixSpan
import ZoneRules

## Independent bounded timeline enumeration for R07 classification.
ZoneRulesTests :: [].{
	expect {
		span = PosixSpan.new(point(-10000000000), point(10000000000))?
		old_rules = ZoneRules.new_bounded("Synthetic/Changed", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 3600 })?
		# Deliberately reuse the same name/version with different contents:
		# metadata is not a substitute for retaining the actual immutable rules.
		new_rules = ZoneRules.new_bounded("Synthetic/Changed", "v1", span, FixedOffset.from_seconds(3600), [], { minimum: 0, maximum: 3600 })?
		other_version = ZoneRules.new_bounded("Synthetic/Changed", "v2", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 3600 })?
		local = local_label(0)?
		original = ResolvedBoundary.resolve(old_rules, local, RequireUnique)?
		changed = ResolvedBoundary.reresolve(original, new_rules)?
		equivalent = ResolvedBoundary.reresolve(original, other_version)?
		end = local_label(1000000)?
		selection = ResolvedSelection.resolve(old_rules, local, end)?
		moved = ResolvedSelection.reresolve(selection, new_rules)?
		same = ResolvedSelection.reresolve(selection, other_version)?
		original_span = PosixSpan.new(point(0), point(1000000))?
		moved_span = PosixSpan.new(point(-3600000000), point(-3599000000))?
		selection_valid = ResolvedSelection.coverage(selection) == Coverage.from_spans([original_span]) and
			ResolvedSelection.coverage(moved) == Coverage.from_spans([moved_span]) and
				ResolvedSelection.same_extent(selection, same) and !ResolvedSelection.same_extent(selection, moved)
		selection_valid and ResolvedBoundary.boundary(original) == point(0) and
			ResolvedBoundary.boundary(changed) == point(-3600000000) and
				!ResolvedBoundary.same_position(original, changed) and
					ResolvedBoundary.same_position(original, equivalent) and
						ResolvedBoundary.source(changed) == local and
							ResolvedBoundary.offset(original) == FixedOffset.from_seconds(0) and
								ZoneRules.offset_at(ResolvedBoundary.rules(original), point(0)) == Ok(FixedOffset.from_seconds(0)) and
									ZoneRules.offset_at(ResolvedBoundary.rules(changed), point(0)) == Ok(FixedOffset.from_seconds(3600))
	}

	expect {
		# Synthetic dateline move: the whole local epoch day is skipped.
		span = PosixSpan.new(point(-259200000000), point(259200000000))?
		rules = ZoneRules.new_bounded(
			"Synthetic/SkippedDay",
			"v1",
			span,
			FixedOffset.from_seconds(0),
			[
				{ at: point(0), offset: FixedOffset.from_seconds(86400) },
			],
			{ minimum: 0, maximum: 86400 },
		)?
		midnight = ClockTime.from_microseconds_since_midnight(0)?
		first = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })?
		second = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 2 })?
		third = CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 3 })?
		expected = PosixSpan.new(point(0), point(86400000000))?
		ZoneRules.select(rules, LocalDateTime.new(first, midnight), LocalDateTime.new(second, midnight)) == Ok(Coverage.from_spans([])) and
			ZoneRules.select(rules, LocalDateTime.new(second, midnight), LocalDateTime.new(third, midnight)) == Ok(Coverage.from_spans([expected]))
	}

	expect {
		span = PosixSpan.new(point(-10000000), point(10000000))?
		rules = ZoneRules.new_bounded("Synthetic/Finite", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
		start = local_label(0)?
		end = local_label(10000000)?
		beyond = local_label(10000001)?
		expected = PosixSpan.new(point(0), point(10000000))?
		# The excluded endpoint may equal validity.end, but never exceed it.
		ZoneRules.select(rules, start, end) == Ok(Coverage.from_spans([expected])) and
			ZoneRules.select(rules, start, beyond) == Err(OutsideValidity)
	}

	expect {
		span = PosixSpan.new(point(-10000000), point(10000000))?
		bad_bounds = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [], { minimum: 1, maximum: -1 }) {
			Err(InvalidOffsetBounds) => Bool.True
			_ => Bool.False
		}
		bad_initial = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(3), [], { minimum: -2, maximum: 2 }) {
			Err(OffsetOutsideBounds) => Bool.True
			_ => Bool.False
		}
		bad_transition = match ZoneRules.new_bounded("Synthetic", "v1", span, FixedOffset.from_seconds(0), [{ at: point(0), offset: FixedOffset.from_seconds(-3) }], { minimum: -2, maximum: 2 }) {
			Err(OffsetOutsideBounds) => Bool.True
			_ => Bool.False
		}
		bad_bounds and bad_initial and bad_transition
	}

	expect {
		var valid = Bool.True
		for first in [-2.I32, 0, 2] {
			for second in [-2.I32, 0, 2] {
				span = PosixSpan.new(point(-10000000), point(10000000))?
				rules = ZoneRules.new_bounded(
					"Synthetic/Enumeration",
					"v1",
					span,
					FixedOffset.from_seconds(0),
					[
						{ at: point(0), offset: FixedOffset.from_seconds(first) },
						{ at: point(4000000), offset: FixedOffset.from_seconds(second) },
					],
					{ minimum: -2, maximum: 2 },
				)?
				var local_second = -7.I64
				while local_second <= 7 {
					for fraction in [0.I64, 1, 999999] {
						number = local_second * 1000000 + fraction
						local = local_label(number)?
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
								expected = expected.append(point(timeline_second * 1000000 + fraction))
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
				edge = local_label(-9000000)?
				valid = valid and ZoneRules.resolve(rules, edge) == Err(OutsideValidity)
			}
		}
		valid
	}

	expect {
		span = PosixSpan.new(point(-10000000), point(10000000))?
		rules = ZoneRules.new_bounded(
			"Synthetic/Triple",
			"v1",
			span,
			FixedOffset.from_seconds(4),
			[
				{ at: point(0), offset: FixedOffset.from_seconds(2) },
				{ at: point(1000000), offset: FixedOffset.from_seconds(0) },
			],
			{ minimum: 0, maximum: 4 },
		)?
		local = local_label(2500000)?
		end = local_label(2750000)?
		var policies_valid = Bool.True
		if ZoneRules.resolve_occurrence(rules, local, RequireUnique) != Err(Ambiguous) or
			ZoneRules.resolve_occurrence(rules, local, First) != Ok(point(-1500000)) or
				ZoneRules.resolve_occurrence(rules, local, Last) != Ok(point(2500000)) or
					ZoneRules.resolve_occurrence(rules, local, MatchingOffset(FixedOffset.from_seconds(2))) != Ok(point(500000)) or
						ZoneRules.resolve_occurrence(rules, local, MatchingOffset(FixedOffset.from_seconds(1))) != Err(OffsetConflict) {
			policies_valid = Bool.False
		}
		appointment = ZoneRules.appointment(rules, local, First, end, Last)?
		whole = PosixSpan.new(point(-1500000), point(2750000))?
		if appointment != whole or
			ZoneRules.appointment(rules, local, Last, end, First) != Err(ReversedBounds) or
				ZoneRules.appointment(rules, local, First, local, First) != Err(EmptySpan) {
			policies_valid = Bool.False
		}
		selected = ZoneRules.select(rules, local, end)?
		a = PosixSpan.new(point(-1500000), point(-1250000))?
		b = PosixSpan.new(point(500000), point(750000))?
		c = PosixSpan.new(point(2500000), point(2750000))?
		policies_valid and ZoneRules.resolve(rules, local) == Ok(Fold([point(-1500000), point(500000), point(2500000)])) and
			selected == Coverage.from_spans([a, b, c]) and
				ZoneRules.select(rules, local, local) == Err(EmptySelection) and
					ZoneRules.select(rules, end, local) == Err(ReversedSelection)
	}
}

point = |number| PosixBoundary.from_microseconds(number)

# Test labels near epoch are formed directly from calendar fields and clock
# positions; do not use FixedOffset.project as an inverse-resolution oracle.
local_label = |number| {
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
