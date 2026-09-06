import fuzz.Fuzz
import time.Persistence
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
		var $reversed = []
		for span in spans {
			$reversed = List.concat([span], $reversed)
		}
		shared = Coverage.from_spans($reversed)
		duplicated = Coverage.from_spans(List.concat(spans, spans))
		backing = List.concat([window], List.concat(spans, [window]))
		sliced = List.sublist(backing, { start: 1, len: List.len(spans) })
		from_slice = Coverage.from_spans(sliced)
		if Dict.get(Dict.insert(Dict.empty(), a, 1.U64), from_slice) != Ok(1) {
			return Ok(Bool.False)
		}
		var $iterated = []
		for member in a {
			$iterated = $iterated.append(member)
		}
		if $iterated != Coverage.to_spans(a) {
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
		check_persistence(a, window, input)
		var $point = -9.I64
		var $width = 0.I64
		var $count = 0.U64
		var $previous = Bool.False
		while $point <= 26 {
			in_a = occupied(input.left, $point)
			in_b = occupied(input.right, $point)
			in_window = input.window.lo <= $point and $point < input.window.lo + U8.to_i64(input.window.width)
			boundary = PosixBoundary.from_microseconds($point)
			if Coverage.contains(a, boundary) != in_a or
				Coverage.contains(union, boundary) != (in_a or in_b) or
					Coverage.contains(intersection, boundary) != (in_a and in_b) or
						Coverage.contains(difference, boundary) != (in_a and !in_b) or
							Coverage.contains(complement, boundary) != (in_window and !in_a) {
				return Ok(Bool.False)
			}
			if in_a {
				$width = $width + 1
			}
			if in_a and !$previous {
				$count = $count + 1
			}
			$previous = in_a
			$point = $point + 1
		}
		Ok(Coverage.coordinate_width(a)? == PosixDelta.from_microseconds($width) and Coverage.member_count(a) == $count)
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
	var $spans = []
	for s in specs {
		$spans = List.append($spans, make_span(s)?)
	}
	Ok($spans)
}

# A point-membership oracle on raw generated fields, independent of coverage.
occupied = |specs, point| {
	var $found = Bool.False
	for s in specs {
		$found = $found or (s.lo <= point and point < s.lo + U8.to_i64(s.width))
	}
	$found
}

# R04/R14: scan every unit cell in the bounded generated domain and emit maximal
# runs from the raw predicate. This oracle never normalizes native spans or
# consults Coverage.to_spans to derive the persisted canonical payload.
check_persistence = |coverage, window, input| {
	var $point = -9.I64
	var $previous = Bool.False
	var $start = 0.I64
	var $runs = []
	while $point <= 26 {
		current = occupied(input.left, $point)
		if current and !$previous {
			$start = $point
		}
		if $previous and !current {
			$runs = $runs.append("${$start.to_str()}/${$point.to_str()}")
		}
		$previous = current
		$point = $point + 1
	}
	expected_payload = Str.join_with($runs, ";")
	check_envelope(Coverage(coverage), "coverage", "posix-canonical-coverage-v1", expected_payload)
	end = input.window.lo + input.window.width.to_i64()
	check_envelope(PosixSpan(window), "posix-span", "posix-half-open-span-v1", "${input.window.lo.to_str()}/${end.to_str()}")
	# Different invalid representations must not be silently normalized during
	# restore: touching, overlapping, duplicated, and out-of-order members.
	lo = input.window.lo
	middle = lo + 1
	hi = lo + 2
	for payload in ["${lo.to_str()}/${middle.to_str()};${middle.to_str()}/${hi.to_str()}", "${lo.to_str()}/${hi.to_str()};${middle.to_str()}/${(hi + 1).to_str()}", "${lo.to_str()}/${middle.to_str()};${lo.to_str()}/${middle.to_str()}", "${hi.to_str()}/${(hi + 1).to_str()};${lo.to_str()}/${middle.to_str()}"] {
		text = Json.to_str({ format: "roc-time", version: "1", kind: "coverage", profile: "posix-canonical-coverage-v1", axis: "posix-1970", unit: "microsecond", payload })
		match Persistence.parse(text) {
			Err(NonCanonicalCoverage) => {}
			_ => crash "Noncanonical persisted coverage was silently normalized"
		}
	}
}

check_envelope = |value, kind, profile, payload| {
	envelope = match Persistence.new(value) {
		Ok(found) => found
		Err(_) => crash "Small native coverage persistence failed"
	}
	text = Persistence.to_text(envelope)
	record : Try({ format : Str, version : Str, kind : Str, profile : Str, axis : Str, unit : Str, payload : Str }, [InvalidJson(Str), MissingRequiredField(Str)])
	record = Json.parse(text)
	match record {
		Ok(fields) => if fields != { format: "roc-time", version: "1", kind, profile, axis: "posix-1970", unit: "microsecond", payload } {
			crash "Persisted coverage differs from independent unit-cell run model"
		}
		Err(_) => crash "Persisted coverage envelope is not seven JSON strings"
	}
	restored = match Persistence.parse(text) {
		Ok(found) => found
		Err(_) => crash "Canonical coverage persistence rejected"
	}
	if Persistence.value(restored) != value or Persistence.to_text(restored) != text {
		crash "Coverage persistence changed native value or canonical text"
	}
}
