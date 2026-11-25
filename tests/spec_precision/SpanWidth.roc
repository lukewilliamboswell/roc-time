import fuzz.Solve
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

SpanWidth := [].{}

# R01 and R03. Two arbitrary I64 boundaries represent a span only when start < end.
# At the lowest start, an end of zero is the first that overflows. Moving the
# start right moves that cutoff equally. Only negative starts can overflow, and
# their distance from I64.lowest fits. Production subtracts start from end.
expect Solve.prove_within(
	{ start: Solve.u64, end: Solve.u64 }.Solve,
	|{ start, end }| {
		lowest = Solve.Uint.from_i64(I64.lowest)
		at_or_past_cutoff = Solve.all([start.lt_signed(0), end.gte_signed(start.minus_signed(lowest))])
		start.lt_signed(end).implies(end.minus_overflows_signed(start).iff(at_or_past_cutoff))
	},
	1000,
) == Ok(Proved)

# Exercise widths immediately below and at the largest representable width,
# then one microsecond beyond it. The span still exists when its width fails.
expect {
	start = PosixBoundary.from_microseconds(I64.lowest)
	var $valid = Bool.True
	for (upper, expected) in [
		(-2.I64, Ok(I64.highest - 1)),
		(-1, Ok(I64.highest)),
		(0, Err(OutOfRange)),
	] {
		end = PosixBoundary.from_microseconds(upper)
		span = PosixSpan.new({ start, end })?
		$valid = $valid and PosixSpan.contains(span, start) and !PosixSpan.contains(span, end) and
			PosixSpan.coordinate_width(span).map_ok(PosixDelta.to_microseconds) == expected
	}
	$valid
}
