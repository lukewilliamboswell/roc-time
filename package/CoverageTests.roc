import Coverage
import PosixBoundary
import PosixDelta
import PosixSpan

CoverageTests :: {}.{}

# All 16 subsets of [-2, 2), independently represented by four integer bits.
from_mask = |mask| {
	var spans = []
	for (point, bit) in [(-2.I64, 1.U64), (-1, 2), (0, 4), (1, 8)] {
		if U64.rem_by(U64.div_trunc_by(mask, bit), 2) == 1 {
			spans = List.append(spans, PosixSpan.microsecond_at(PosixBoundary.from_microseconds(point))?)
		}
	}
	Ok(Coverage.from_spans(spans))
}

expect {
	window = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(2))?
	universe = Coverage.from_spans([window])
	var valid = Bool.True
	var x = 0.U64
	while x < 16 {
		a = from_mask(x)?
		valid = valid and Coverage.from_spans(Coverage.to_spans(a)) == a
		valid = valid and Coverage.union(a, a) == a and Coverage.intersection(a, a) == a
		complement = Coverage.complement_within(a, window)
		valid = valid and Coverage.union(a, complement) == universe
		valid = valid and Coverage.intersection(a, complement) == Coverage.empty
		var expected_width = 0.I64
		var expected_members = 0.U64
		var previous = Bool.False
		for bit in [1.U64, 2, 4, 8] {
			occupied = U64.rem_by(U64.div_trunc_by(x, bit), 2) == 1
			if occupied {
				expected_width = expected_width + 1
			}
			if occupied and !previous {
				expected_members = expected_members + 1
			}
			previous = occupied
		}
		valid = valid and Coverage.coordinate_width(a) == Ok(PosixDelta.from_microseconds(expected_width))
		valid = valid and Coverage.member_count(a) == expected_members
		var y = 0.U64
		while y < 16 {
			b = from_mask(y)?
			union = Coverage.union(a, b)
			intersection = Coverage.intersection(a, b)
			difference = Coverage.difference(a, b)
			valid = valid and union == Coverage.union(b, a)
			valid = valid and intersection == Coverage.intersection(b, a)
			valid = valid and Coverage.intersection(difference, b) == Coverage.empty
			valid = valid and Coverage.union(difference, intersection) == a
			for (point, bit) in [(-2.I64, 1.U64), (-1, 2), (0, 4), (1, 8)] {
				in_a = U64.rem_by(U64.div_trunc_by(x, bit), 2) == 1
				in_b = U64.rem_by(U64.div_trunc_by(y, bit), 2) == 1
				boundary = PosixBoundary.from_microseconds(point)
				valid = valid and Coverage.contains(a, boundary) == in_a
				valid = valid and Coverage.contains(union, boundary) == (in_a or in_b)
				valid = valid and Coverage.contains(intersection, boundary) == (in_a and in_b)
				valid = valid and Coverage.contains(difference, boundary) == (in_a and !in_b)
				valid = valid and Coverage.contains(complement, boundary) == !in_a
			}
			for outside in [-3.I64, 2] {
				point = PosixBoundary.from_microseconds(outside)
				valid = valid and !Coverage.contains(union, point)
				valid = valid and !Coverage.contains(difference, point)
				valid = valid and !Coverage.contains(complement, point)
			}
			y = y + 1
		}
		x = x + 1
	}
	valid
}

# Arbitrarily overlapping inputs, duplicate spans, reverse order, and queries
# clipping each possible endpoint. Compare directly to integer membership.
expect {
	var valid = Bool.True
	for a in [-2.I64, -1, 0, 1] {
		for b in [-1.I64, 0, 1, 2] {
			for c in [-2.I64, -1, 0, 1] {
				for d in [-1.I64, 0, 1, 2] {
					if a < b and c < d {
						left = PosixSpan.new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b))?
						right = PosixSpan.new(PosixBoundary.from_microseconds(c), PosixBoundary.from_microseconds(d))?
						coverage = Coverage.from_spans([left, right, left])
						valid = valid and coverage == Coverage.from_spans([right, left])
						clipped = Coverage.intersection(coverage, Coverage.from_spans([left]))
						complement = Coverage.complement_within(Coverage.from_spans([right]), left)
						valid = valid and Coverage.union(complement, Coverage.intersection(Coverage.from_spans([right]), Coverage.from_spans([left]))) == Coverage.from_spans([left])
						matches = Coverage.overlapping_spans(coverage, left)
						count = Coverage.fold_overlaps(coverage, left, 0.U64, |n, _| n + 1)
						valid = valid and count == List.len(matches)
						# Linear query oracle includes only whole overlapping members.
						var expected_matches = []
						for member in Coverage.to_spans(coverage) {
							if PosixSpan.overlaps(member, left) {
								expected_matches = List.append(expected_matches, member)
							}
						}
						valid = valid and matches == expected_matches
						for p in [-3.I64, -2, -1, 0, 1, 2, 3] {
							point = PosixBoundary.from_microseconds(p)
							occupied = (a <= p and p < b) or (c <= p and p < d)
							valid = valid and Coverage.contains(coverage, point) == occupied
							valid = valid and Coverage.contains(clipped, point) == (a <= p and p < b)
							valid = valid and Coverage.contains(complement, point) == (a <= p and p < b and !(c <= p and p < d))
						}
					}
				}
			}
		}
	}
	valid
}

expect {
	early = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(0))?
	late = PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(2))?
	Coverage.from_sorted_spans([early, late]) == Ok(Coverage.from_spans([late, early])) and
		Coverage.from_sorted_spans([late, early]) == Err(UnsortedInput)
}

expect {
	wide = PosixSpan.new(PosixBoundary.from_microseconds(-9223372036854775808), PosixBoundary.from_microseconds(-1))?
	unit = PosixSpan.microsecond_at(PosixBoundary.from_microseconds(0))?
	Coverage.coordinate_width(Coverage.from_spans([wide, unit])) == Err(OutOfRange)
}

expect {
	unit = PosixSpan.microsecond_at(PosixBoundary.from_microseconds(9223372036854775806))?
	coverage = Coverage.from_spans([unit])
	Coverage.contains(coverage, PosixSpan.start(unit)) and !Coverage.contains(coverage, PosixSpan.end(unit)) and
		Coverage.complement_within(coverage, unit) == Coverage.empty
}
