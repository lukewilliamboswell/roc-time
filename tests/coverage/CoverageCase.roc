import fuzz.Fuzz
import time.Coverage
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

Spec : { lo : I64, width : U8 }

spec = { lo: Fuzz.map(Fuzz.u8_in(0, 16), |n| U8.to_i64(n) - 8), width: Fuzz.u8_in(1, 17) }.Fuzz

CoverageCase := { left : List(Spec), right : List(Spec), window : Spec }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(CoverageCase)
	generator_for = |_| { left: Fuzz.list(spec, 16), right: Fuzz.list(spec, 16), window: spec }.Fuzz

	evaluate : CoverageCase -> Try(Bool, [EmptySpan, ReversedBounds, OutOfRange, ..])
	evaluate = |input| {
		spans = make_spans(input.left)?
		a = Coverage.from_spans(spans)
		b = Coverage.from_spans(make_spans(input.right)?)
		window = make_span(input.window)?
		# Owned construction, shared input, reversed/duplicated input, and a slice
		# retaining a larger allocation must all have identical extents.
		owned = Coverage.from_spans(make_spans(input.left)?)
		var reversed = []
		for span in spans {
			reversed = List.concat([span], reversed)
		}
		shared = Coverage.from_spans(reversed)
		duplicated = Coverage.from_spans(List.concat(spans, spans))
		backing = List.concat([window], List.concat(spans, [window]))
		sliced = List.sublist(backing, { start: 1, len: List.len(spans) })
		from_slice = Coverage.from_spans(sliced)
		if Dict.get(Dict.insert(Dict.empty(), a, 1.U64), from_slice) != Ok(1) {
			return Ok(Bool.False)
		}
		var iterated = []
		for member in a {
			iterated = iterated.append(member)
		}
		if iterated != Coverage.to_spans(a) {
			return Ok(Bool.False)
		}
		if a != owned or a != shared or a != duplicated or a != from_slice {
			return Ok(Bool.False)
		}
		# Use retained inputs after construction so ownership/sharing stays live.
		if List.len(backing) != List.len(spans) + 2 or List.len(sliced) != List.len(spans) {
			return Ok(Bool.False)
		}
		if spans != make_spans(input.left)? or sliced != spans or backing != List.concat([window], List.concat(spans, [window])) {
			return Ok(Bool.False)
		}
		if Coverage.from_spans(Coverage.to_spans(a)) != a {
			return Ok(Bool.False)
		}
		union = Coverage.union(a, b)
		intersection = Coverage.intersection(a, b)
		difference = Coverage.difference(a, b)
		complement = Coverage.complement_within(a, window)
		if Coverage.union(b, a) != union or Coverage.intersection(b, a) != intersection {
			return Ok(Bool.False)
		}
		if Coverage.union(a, a) != a or Coverage.intersection(a, a) != a {
			return Ok(Bool.False)
		}
		if Coverage.intersection(difference, b) != Coverage.empty {
			return Ok(Bool.False)
		}
		if Coverage.union(difference, intersection) != a {
			return Ok(Bool.False)
		}
		if Coverage.union(complement, Coverage.intersection(a, Coverage.from_spans([window]))) != Coverage.from_spans([window]) {
			return Ok(Bool.False)
		}
		var point = -9.I64
		var width = 0.I64
		var count = 0.U64
		var previous = Bool.False
		while point <= 26 {
			in_a = occupied(input.left, point)
			in_b = occupied(input.right, point)
			in_window = input.window.lo <= point and point < input.window.lo + U8.to_i64(input.window.width)
			boundary = PosixBoundary.from_microseconds(point)
			if Coverage.contains(a, boundary) != in_a or
				Coverage.contains(union, boundary) != (in_a or in_b) or
					Coverage.contains(intersection, boundary) != (in_a and in_b) or
						Coverage.contains(difference, boundary) != (in_a and !in_b) or
							Coverage.contains(complement, boundary) != (in_window and !in_a) {
				return Ok(Bool.False)
			}
			if in_a {
				width = width + 1
			}
			if in_a and !previous {
				count = count + 1
			}
			previous = in_a
			point = point + 1
		}
		Ok(Coverage.coordinate_width(a)? == PosixDelta.from_microseconds(width) and Coverage.member_count(a) == count)
	}

	check : CoverageCase -> Fuzz.Outcome
	check = |input| {
		match evaluate(input) {
			Ok(Bool.True) => Fuzz.keep
			Ok(Bool.False) => crash "R04 coverage differs from membership oracle or algebraic law"
			Err(_) => crash "R04 bounded valid generated input was rejected"
		}
	}
}

make_span = |s| PosixSpan.new(PosixBoundary.from_microseconds(s.lo), PosixBoundary.from_microseconds(s.lo + U8.to_i64(s.width)))

make_spans = |specs| {
	var spans = []
	for s in specs {
		spans = List.append(spans, make_span(s)?)
	}
	Ok(spans)
}

# A point-membership oracle on raw generated fields, independent of coverage.
occupied = |specs, point| {
	var found = Bool.False
	for s in specs {
		found = found or (s.lo <= point and point < s.lo + U8.to_i64(s.width))
	}
	found
}
