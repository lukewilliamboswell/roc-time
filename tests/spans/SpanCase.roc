import fuzz.Fuzz
import time.PosixBoundary
import time.PosixSpan

endpoint = Fuzz.map2(
	Fuzz.u8_in(0, 7),
	Fuzz.u64,
	|choice, raw| {
		match choice {
			0 => I64.lowest
			1 => I64.highest
			2 => -1.I64
			3 => 0.I64
			4 => 1.I64
			_ => U64.to_i64_wrap(raw)
		}
	},
)

SpanCase := { a : I64, b : I64, c : I64, d : I64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(SpanCase)
	generator_for = |_| { a: endpoint, b: endpoint, c: endpoint, d: endpoint }.Fuzz

	evaluate : SpanCase -> Try(Bool, [EmptySpan, ReversedBounds, ..])
	evaluate = |input| {
		for (a, b) in [(input.a, input.b), (input.c, input.d)] {
			constructed = PosixSpan.new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b))
			if a == b and constructed != Err(EmptySpan) {
				return Ok(Bool.False)
			}
			if a > b and constructed != Err(ReversedBounds) {
				return Ok(Bool.False)
			}
			if a < b {
				span = constructed?
				if PosixBoundary.to_microseconds(PosixSpan.start(span)) != a or
					PosixBoundary.to_microseconds(PosixSpan.end(span)) != b {
					return Ok(Bool.False)
				}
			}
		}
		# Retain the retired target's small-domain membership oracle alongside the
		# full-range relation checks. Signed remainders lie in [-8, 8].
		small_left = ordered_span(I64.rem_by(input.a, 9), I64.rem_by(input.b, 9))?
		small_right = ordered_span(I64.rem_by(input.c, 9), I64.rem_by(input.d, 9))?
		small_a = PosixBoundary.to_microseconds(PosixSpan.start(small_left))
		small_b = PosixBoundary.to_microseconds(PosixSpan.end(small_left))
		small_c = PosixBoundary.to_microseconds(PosixSpan.start(small_right))
		small_d = PosixBoundary.to_microseconds(PosixSpan.end(small_right))
		var point = -9.I64
		var shared = Bool.False
		while point <= 9 {
			in_left = small_a <= point and point < small_b
			in_right = small_c <= point and point < small_d
			boundary = PosixBoundary.from_microseconds(point)
			if PosixSpan.contains(small_left, boundary) != in_left or PosixSpan.contains(small_right, boundary) != in_right {
				return Ok(Bool.False)
			}
			shared = shared or (in_left and in_right)
			point = point + 1
		}
		if PosixSpan.overlaps(small_left, small_right) != shared {
			return Ok(Bool.False)
		}
		left = ordered_span(input.a, input.b)?
		right = ordered_span(input.c, input.d)?
		a = PosixBoundary.to_microseconds(PosixSpan.start(left))
		b = PosixBoundary.to_microseconds(PosixSpan.end(left))
		c = PosixBoundary.to_microseconds(PosixSpan.start(right))
		d = PosixBoundary.to_microseconds(PosixSpan.end(right))
		# Independent order predicates, rather than the production decision tree.
		correct = match PosixSpan.relation(left, right) {
			Before => b < c
			Meets => b == c
			Overlaps => a < c and c < b and b < d
			Starts => a == c and b < d
			During => c < a and b < d
			Finishes => c < a and b == d
			Equal => a == c and b == d
			FinishedBy => a < c and b == d
			Contains => a < c and d < b
			StartedBy => a == c and d < b
			OverlappedBy => c < a and a < d and d < b
			MetBy => a == d
			After => d < a
		}
		inverse = match PosixSpan.relation(right, left) {
			Before => After
			Meets => MetBy
			Overlaps => OverlappedBy
			Starts => StartedBy
			During => Contains
			Finishes => FinishedBy
			Equal => Equal
			FinishedBy => Finishes
			Contains => During
			StartedBy => Starts
			OverlappedBy => Overlaps
			MetBy => Meets
			After => Before
		}
		Ok(correct and PosixSpan.relation(left, right) == inverse and PosixSpan.overlaps(left, right) == (a < d and c < b))
	}

	check : SpanCase -> Fuzz.Outcome
	check = |input| {
		match evaluate(input) {
			Ok(Bool.True) => Fuzz.keep
			Ok(Bool.False) => crash "R03 span or relation disagrees with order oracle"
			Err(_) => crash "R03 valid generated span was rejected"
		}
	}
}

# Preserve invalid constructor cases as tested errors, then produce a valid span
# for relation checks. Equal endpoints expand to a unit span without overflow.
ordered_span = |a, b| {
	lower = if a < b {
		a
	} else if a > b {
		b
	} else if a == I64.highest {
		a - 1
	} else {
		a
	}
	upper = if a < b {
		b
	} else if a > b {
		a
	} else if a == I64.highest {
		a
	} else {
		a + 1
	}
	PosixSpan.new(PosixBoundary.from_microseconds(lower), PosixBoundary.from_microseconds(upper))
}
