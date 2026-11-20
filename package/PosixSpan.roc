import MicrosecondRounding
import PosixBoundary
import PosixDelta

## A finite, nonempty half-open span on the POSIX microsecond axis.
##
## Example
##
## Construct a half-open interval: the start belongs to it and the end does not.
## Equal endpoints return `EmptySpan`; reversed endpoints return `ReversedBounds`.
##
## ```roc
## import time.PosixBoundary
## import time.PosixSpan
##
## expect {
##     start = PosixBoundary.from_microseconds(0)
##     end = PosixBoundary.from_microseconds(1000000)
##     span = PosixSpan.new({ start, end })?
##     PosixSpan.contains(span, start) and !PosixSpan.contains(span, end)
## }
## ```
##
## Examples assume a package dependency named `time`.
PosixSpan :: { start : PosixBoundary, end : PosixBoundary }.{

	## Construct a nonempty half-open span [start, end). Equal endpoints return
	## EmptySpan; a start after the end returns ReversedBounds.
	new : { start : PosixBoundary, end : PosixBoundary } -> Try(PosixSpan, [EmptySpan, ReversedBounds])
	new = |{ start: start_value, end: end_value }| {
		match PosixBoundary.order_relative_to(start_value, end_value) {
			Before => Ok({ start: start_value, end: end_value })
			Same => Err(EmptySpan)
			After => Err(ReversedBounds)
		}
	}

	## Interpret decimal seconds since the POSIX epoch with one rounding policy
	## for both endpoints. Equal/reversed source bounds are rejected before
	## conversion; rounding that collapses a nonempty span returns EmptySpan.
	from_seconds : { start : Dec, end : Dec, rounding : MicrosecondRounding } -> Try(PosixSpan, [EmptySpan, ReversedBounds, Submicrosecond, OutOfRange])
	from_seconds = |{ start: lo, end: hi, rounding: policy }| {
		if lo == hi {
			return Err(EmptySpan)
		}
		if lo > hi {
			return Err(ReversedBounds)
		}
		start_value = PosixBoundary.from_seconds(lo, policy)?
		end_value = PosixBoundary.from_seconds(hi, policy)?
		new({ start: start_value, end: end_value })
	}

	## Read the inclusive lower boundary of this span.
	start : PosixSpan -> PosixBoundary
	start = |span| span.start

	## Read the exclusive upper boundary; that position is not contained in the span.
	end : PosixSpan -> PosixBoundary
	end = |span| span.end

	## Return end minus start as a POSIX displacement. A valid span can still
	## return OutOfRange when its width exceeds I64 microseconds.
	coordinate_width : PosixSpan -> Try(PosixDelta, [OutOfRange])
	coordinate_width = |span| PosixBoundary.difference({ left: span.end, right: span.start })

	## Construct [point, point + one microsecond). The greatest representable
	## position returns OutOfRange because its exclusive end cannot be represented.
	microsecond_at : PosixBoundary -> Try(PosixSpan, [OutOfRange])
	microsecond_at = |point| {
		upper = PosixBoundary.shift(point, PosixDelta.from_microseconds(1))?
		# Checked positive shift proves point < upper; no revalidation needed.
		Ok({ start: point, end: upper })
	}

	## Hash both boundaries consistently with span equality for dictionary/set keys.
	to_hash : PosixSpan, Hasher -> Hasher
	to_hash = |span, hasher| span.end.to_hash(span.start.to_hash(hasher))

	## Describe the half-open boundaries in POSIX microseconds for diagnostics.
	## Use ExactInterval for supported interval text interchange.
	to_inspect : PosixSpan -> Str
	to_inspect = |span| "PosixSpan([${PosixBoundary.to_microseconds(span.start).to_str()}, ${PosixBoundary.to_microseconds(span.end).to_str()}) microseconds)"

	## Compare both boundaries for equal extent. Span identity and source spelling
	## are not part of this equality.
	is_eq : PosixSpan, PosixSpan -> Bool
	is_eq = |a, b| a.start == b.start and a.end == b.end

	## The smallest span containing both inputs, including any gap between them.
	hull : PosixSpan, PosixSpan -> PosixSpan
	hull = |a, b| {
		lower = if PosixBoundary.order_relative_to(a.start, b.start) == Before {
			a.start
		} else {
			b.start
		}
		upper = if PosixBoundary.order_relative_to(a.end, b.end) == After {
			a.end
		} else {
			b.end
		}
		{ start: lower, end: upper }
	}

	## Return the common nonempty span, or Empty when inputs are disjoint or
	## only touch at an endpoint.
	intersection : PosixSpan, PosixSpan -> [Empty, Span(PosixSpan)]
	intersection = |a, b| {
		lower = if PosixBoundary.order_relative_to(a.start, b.start) == After {
			a.start
		} else {
			b.start
		}
		upper = if PosixBoundary.order_relative_to(a.end, b.end) == Before {
			a.end
		} else {
			b.end
		}
		if PosixBoundary.order_relative_to(lower, upper) == Before {
			Span({ start: lower, end: upper })
		} else {
			Empty
		}
	}

	## Whether the spans share any occupied position. Touching endpoints alone
	## do not overlap because the upper boundary is exclusive.
	overlaps : PosixSpan, PosixSpan -> Bool
	overlaps = |a, b| {
		PosixBoundary.order_relative_to(a.start, b.end) == Before and PosixBoundary.order_relative_to(b.start, a.end) == Before
	}

	## Whether a position is at or after start and strictly before end.
	contains : PosixSpan, PosixBoundary -> Bool
	contains = |span, point| {
		PosixBoundary.order_relative_to(span.start, point) != After and PosixBoundary.order_relative_to(point, span.end) == Before
	}

	## Classify the first span relative to the second using the thirteen Allen
	## interval relations. Meets and MetBy describe touching without overlap.
	relation : { left : PosixSpan, right : PosixSpan } -> [Before, Meets, Overlaps, Starts, During, Finishes, Equal, FinishedBy, Contains, StartedBy, OverlappedBy, MetBy, After]
	relation = |{ left: a, right: b }| {
		if PosixBoundary.order_relative_to(a.end, b.start) == Before {
			return Before
		}
		if a.end == b.start {
			return Meets
		}
		if PosixBoundary.order_relative_to(a.start, b.end) == After {
			return After
		}
		if a.start == b.end {
			return MetBy
		}
		match (PosixBoundary.order_relative_to(a.start, b.start), PosixBoundary.order_relative_to(a.end, b.end)) {
			(Before, Before) => Overlaps
			(Before, Same) => FinishedBy
			(Before, After) => Contains
			(Same, Before) => Starts
			(Same, Same) => Equal
			(Same, After) => StartedBy
			(After, Before) => During
			(After, Same) => Finishes
			(After, After) => OverlappedBy
		}
	}

	expect new({ start: PosixBoundary.from_microseconds(0), end: PosixBoundary.from_microseconds(0) }) == Err(EmptySpan)
	expect new({ start: PosixBoundary.from_microseconds(1), end: PosixBoundary.from_microseconds(0) }) == Err(ReversedBounds)

	expect microsecond_at(PosixBoundary.from_microseconds(9223372036854775807)) == Err(OutOfRange)
	expect from_seconds({ start: 0.0000001.Dec, end: 0.0000002.Dec, rounding: Floor }) == Err(EmptySpan)
	expect from_seconds({ start: 0.0000002.Dec, end: 0.0000001.Dec, rounding: Ceiling }) == Err(ReversedBounds)
	expect {
		span = new({ start: PosixBoundary.from_microseconds(-9223372036854775808), end: PosixBoundary.from_microseconds(9223372036854775807) })?
		coordinate_width(span) == Err(OutOfRange)
	}

	# One representative for each strict endpoint ordering, including inverses.
	expect {
		anchor = new({ start: PosixBoundary.from_microseconds(0), end: PosixBoundary.from_microseconds(3) })?
		var $valid = Bool.True
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
			other = new({ start: PosixBoundary.from_microseconds(lo), end: PosixBoundary.from_microseconds(hi) })?
			$valid = $valid and relation({ left: anchor, right: other }) == expected
		}
		$valid
	}

	## Exhaustively compare overlap to occupied integer points on a small axis.
	## Includes negative coordinates, touching and one-microsecond spans.
	expect {
		var $valid = Bool.True
		for a in [-2.I64, -1, 0, 1] {
			for b in [-1.I64, 0, 1, 2] {
				for c in [-2.I64, -1, 0, 1] {
					for d in [-1.I64, 0, 1, 2] {
						if a < b and c < d {
							left = new({ start: PosixBoundary.from_microseconds(a), end: PosixBoundary.from_microseconds(b) })?
							right = new({ start: PosixBoundary.from_microseconds(c), end: PosixBoundary.from_microseconds(d) })?
							var $shared = Bool.False
							for p in [-2.I64, -1, 0, 1, 2] {
								$shared = $shared or (a <= p and p < b and c <= p and p < d)
							}
							$valid = $valid and overlaps(left, right) == $shared
							# Relations agree with inverse classification and overlap semantics.
							inverse = match relation({ left, right }) {
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
							$valid = $valid and relation({ left: right, right: left }) == inverse
						}
					}
				}
			}
		}
		$valid
	}
}
