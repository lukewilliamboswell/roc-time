import PosixBoundary
import PosixDelta

## A finite, nonempty half-open span on the POSIX microsecond axis.
PosixSpan :: { start : PosixBoundary, end : PosixBoundary }.{
	new : PosixBoundary, PosixBoundary -> Try(PosixSpan, [EmptySpan, ReversedBounds, ..])
	new = |start, end| {
		match PosixBoundary.compare(start, end) {
			LT => Ok({ start, end })
			EQ => Err(EmptySpan)
			GT => Err(ReversedBounds)
		}
	}

	## Apply one explicit rounding policy to both endpoints, then validate.
	from_seconds : Dec, Dec, PosixBoundary.Rounding -> Try(PosixSpan, [EmptySpan, ReversedBounds, Submicrosecond, OutOfRange, ..])
	from_seconds = |lo, hi, policy| {
		if lo == hi {
			return Err(EmptySpan)
		}
		if lo > hi {
			return Err(ReversedBounds)
		}
		start = PosixBoundary.from_seconds(lo, policy)?
		end = PosixBoundary.from_seconds(hi, policy)?
		new(start, end)
	}

	start : PosixSpan -> PosixBoundary
	start = |span| span.start

	end : PosixSpan -> PosixBoundary
	end = |span| span.end

	coordinate_width : PosixSpan -> Try(PosixDelta, [OutOfRange, ..])
	coordinate_width = |span| PosixBoundary.difference(span.end, span.start)

	microsecond_at : PosixBoundary -> Try(PosixSpan, [OutOfRange, ..])
	microsecond_at = |point| {
		upper = PosixBoundary.shift(point, PosixDelta.from_microseconds(1))?
		# Checked positive shift proves point < upper; no revalidation needed.
		Ok({ start: point, end: upper })
	}

	to_hash : PosixSpan, Hasher -> Hasher
	to_hash = |span, hasher| span.end.to_hash(span.start.to_hash(hasher))

	to_inspect : PosixSpan -> Str
	to_inspect = |span| "PosixSpan([${PosixBoundary.to_microseconds(span.start).to_str()}, ${PosixBoundary.to_microseconds(span.end).to_str()}) microseconds)"

	is_eq : PosixSpan, PosixSpan -> Bool
	is_eq = |a, b| a.start == b.start and a.end == b.end

	## The smallest span containing both inputs, including any gap between them.
	hull : PosixSpan, PosixSpan -> PosixSpan
	hull = |a, b| {
		lower = if PosixBoundary.compare(a.start, b.start) == LT {
			a.start
		} else {
			b.start
		}
		upper = if PosixBoundary.compare(a.end, b.end) == GT {
			a.end
		} else {
			b.end
		}
		{ start: lower, end: upper }
	}

	intersection : PosixSpan, PosixSpan -> [Empty, Span(PosixSpan)]
	intersection = |a, b| {
		lower = if PosixBoundary.compare(a.start, b.start) == GT {
			a.start
		} else {
			b.start
		}
		upper = if PosixBoundary.compare(a.end, b.end) == LT {
			a.end
		} else {
			b.end
		}
		if PosixBoundary.compare(lower, upper) == LT {
			Span({ start: lower, end: upper })
		} else {
			Empty
		}
	}

	overlaps : PosixSpan, PosixSpan -> Bool
	overlaps = |a, b| {
		PosixBoundary.compare(a.start, b.end) == LT and PosixBoundary.compare(b.start, a.end) == LT
	}

	contains : PosixSpan, PosixBoundary -> Bool
	contains = |span, point| {
		PosixBoundary.compare(span.start, point) != GT and PosixBoundary.compare(point, span.end) == LT
	}

	relation : PosixSpan, PosixSpan -> [Before, Meets, Overlaps, Starts, During, Finishes, Equal, FinishedBy, Contains, StartedBy, OverlappedBy, MetBy, After]
	relation = |a, b| {
		if PosixBoundary.compare(a.end, b.start) == LT {
			return Before
		}
		if a.end == b.start {
			return Meets
		}
		if PosixBoundary.compare(a.start, b.end) == GT {
			return After
		}
		if a.start == b.end {
			return MetBy
		}
		match (PosixBoundary.compare(a.start, b.start), PosixBoundary.compare(a.end, b.end)) {
			(LT, LT) => Overlaps
			(LT, EQ) => FinishedBy
			(LT, GT) => Contains
			(EQ, LT) => Starts
			(EQ, EQ) => Equal
			(EQ, GT) => StartedBy
			(GT, LT) => During
			(GT, EQ) => Finishes
			(GT, GT) => OverlappedBy
		}
	}

	expect new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(0)) == Err(EmptySpan)
	expect new(PosixBoundary.from_microseconds(1), PosixBoundary.from_microseconds(0)) == Err(ReversedBounds)

	expect microsecond_at(PosixBoundary.from_microseconds(9223372036854775807)) == Err(OutOfRange)
	expect from_seconds(0.0000001.Dec, 0.0000002.Dec, Floor) == Err(EmptySpan)
	expect from_seconds(0.0000002.Dec, 0.0000001.Dec, Ceiling) == Err(ReversedBounds)
	expect {
		span = new(PosixBoundary.from_microseconds(-9223372036854775808), PosixBoundary.from_microseconds(9223372036854775807))?
		coordinate_width(span) == Err(OutOfRange)
	}

	## One representative for each strict endpoint ordering, including inverses.
	expect {
		anchor = new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3))?
		var valid = Bool.True
		for (lo, hi, expected) in [
			(4.I64, 5.I64, Before),
			(3, 4, Meets),
			(2, 4, Overlaps),
			(0, 4, Starts),
			(-1, 4, During),
			(-1, 3, Finishes),
			(0, 3, Equal),
			(1, 3, FinishedBy),
			(1, 2, Contains),
			(0, 2, StartedBy),
			(-1, 2, OverlappedBy),
			(-1, 0, MetBy),
			(-2, -1, After),
		] {
			other = new(PosixBoundary.from_microseconds(lo), PosixBoundary.from_microseconds(hi))?
			valid = valid and relation(anchor, other) == expected
		}
		valid
	}

	## Exhaustively compare overlap to occupied integer points on a small axis.
	## Includes negative coordinates, touching and one-microsecond spans.
	expect {
		var valid = Bool.True
		for a in [-2.I64, -1, 0, 1] {
			for b in [-1.I64, 0, 1, 2] {
				for c in [-2.I64, -1, 0, 1] {
					for d in [-1.I64, 0, 1, 2] {
						if a < b and c < d {
							left = new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b))?
							right = new(PosixBoundary.from_microseconds(c), PosixBoundary.from_microseconds(d))?
							var shared = Bool.False
							for p in [-2.I64, -1, 0, 1, 2] {
								shared = shared or (a <= p and p < b and c <= p and p < d)
							}
							valid = valid and overlaps(left, right) == shared
							# Relations agree with inverse classification and overlap semantics.
							inverse = match relation(left, right) {
								Before => After
								After => Before
								Meets => MetBy
								MetBy => Meets
								Overlaps => OverlappedBy
								OverlappedBy => Overlaps
								Starts => StartedBy
								StartedBy => Starts
								During => Contains
								Contains => During
								Finishes => FinishedBy
								FinishedBy => Finishes
								Equal => Equal
							}
							valid = valid and relation(right, left) == inverse
						}
					}
				}
			}
		}
		valid
	}
}
