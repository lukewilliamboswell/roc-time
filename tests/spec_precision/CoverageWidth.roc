import fuzz.Solve
import time.Coverage
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

CoverageWidth := [].{}

# R01 and R04. Each of two positive I64 member widths fits separately.
# Their exact sum fits U64, which independently determines whether their
# signed accumulator must reject it.
expect {
	maximum = I64.highest.to_u64_wrap()
	positive_width = Solve.u64_in(1, maximum)
	Solve.prove_within(
		{ first: positive_width, second: positive_width }.Solve,
		|{ first, second }|
			first.plus_overflows_signed(second).iff((first + second).gt(Solve.Uint.from_u64(maximum))),
		1000,
	) == Ok(Proved)
}

# The three-microsecond gap makes the enclosing hull too wide for I64 even
# when the occupied width still fits. The first member occupies max - 2.
expect {
	point = PosixBoundary.from_microseconds
	first = PosixSpan.new({ start: point(I64.lowest), end: point(-3) })?
	var $valid = Bool.True
	for (end, expected) in [
		(1.I64, Ok(I64.highest - 1)),
		(2, Ok(I64.highest)),
		(3, Err(OutOfRange)),
	] {
		second = PosixSpan.new({ start: point(0), end: point(end) })?
		coverage = Coverage.from_spans([second, first])
		$valid = $valid and Coverage.member_count(coverage) == 2 and
			Coverage.coordinate_width(coverage).map_ok(PosixDelta.to_microseconds) == expected
	}
	$valid
}
