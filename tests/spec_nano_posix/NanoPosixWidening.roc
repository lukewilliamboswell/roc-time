import fuzz.Solve
import time.PosixBoundary
import time.PosixDelta
import time.Nanosecond.PosixBoundary as PosixNanoBoundary
import time.Nanosecond.PosixDelta as PosixNanoDelta

NanoPosixWidening := [].{}

# An exporter converting a microsecond position or displacement to
# an I64 nanosecond column may use the closed interval between the first and
# last whole microseconds in that carrier.
first = -9_223_372_036_854_775.I64

last = 9_223_372_036_854_775.I64

expect Solve.prove_within(
	Solve.u64,
	|microseconds| {
		out_of_range = Solve.any([
			microseconds.lt_signed(Solve.Uint.from_i64(first)),
			microseconds.gt_signed(Solve.Uint.from_i64(last)),
		])
		microseconds.times_overflows_signed(1000).iff(out_of_range)
	},
	1000,
) == Ok(Proved)

# The same cutoffs apply to both nominal conversions. Check their exact
# results at each limit, the adjacent inputs, and the epoch against an I128
# product whose range covers all I64 microsecond inputs.
expect {
	var $valid = Bool.True
	for microseconds in [I64.lowest, first - 1, first, first + 1, -1, 0, 1, last - 1, last, last + 1, I64.highest] {
		product = microseconds.to_i128() * 1000
		expected = product.to_i64_try()
		boundary = PosixNanoBoundary.from_boundary(PosixBoundary.from_microseconds(microseconds))
		delta = PosixNanoDelta.from_delta(PosixDelta.from_microseconds(microseconds))
		$valid = $valid and
			boundary.map_ok(PosixNanoBoundary.to_nanoseconds) == expected and
				delta.map_ok(PosixNanoDelta.to_nanoseconds) == expected
	}
	$valid
}
