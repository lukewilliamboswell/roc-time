import PosixDelta
import MicrosecondRounding
import Quantize

## Signed POSIX coordinate displacement in whole nanoseconds.
PosixNanoDelta :: I64.{

	## Construct from any signed I64 nanosecond count.
	from_nanoseconds : I64 -> PosixNanoDelta
	from_nanoseconds = |value| PosixNanoDelta.(value)

	## Read the exact signed nanosecond count.
	to_nanoseconds : PosixNanoDelta -> I64
	to_nanoseconds = |PosixNanoDelta.(value)| value

	## Convert a microsecond value when its scaled count fits I64.
	from_delta : PosixDelta -> Try(PosixNanoDelta, [OutOfRange])
	from_delta = |value| {
		count = value.to_microseconds().times_try(1000) ? |_| OutOfRange
		Ok(from_nanoseconds(count))
	}

	## Convert exactly to the microsecond domain, rejecting fractional microseconds.
	to_delta : PosixNanoDelta -> Try(PosixDelta, [Submicrosecond])
	to_delta = |value| value.to_delta_with_rounding(RejectSubmicrosecond)

	## Convert to the microsecond domain using the supplied rounding policy.
	to_delta_with_rounding : PosixNanoDelta, MicrosecondRounding -> Try(PosixDelta, [Submicrosecond])
	to_delta_with_rounding = |PosixNanoDelta.(value), rounding| {
		result = Quantize.to_microseconds({ value, divisor: 1000, rounding })?
		Ok(PosixDelta.from_microseconds(result))
	}

	## Compare exact signed nanosecond counts within this domain.
	is_eq : _

	## Hash the signed nanosecond count consistently with equality.
	to_hash : _

	## Order by signed nanosecond count.
	order_relative_to : PosixNanoDelta, PosixNanoDelta -> [Before, Same, After]
	order_relative_to = |PosixNanoDelta.(left), PosixNanoDelta.(right)| left.order_relative_to(right)

	## Whether the first coordinate is less than the second.
	is_lt : PosixNanoDelta, PosixNanoDelta -> Bool
	is_lt = |PosixNanoDelta.(left), PosixNanoDelta.(right)| left < right

	## Whether the first coordinate is less than or equal to the second.
	is_lte : PosixNanoDelta, PosixNanoDelta -> Bool
	is_lte = |PosixNanoDelta.(left), PosixNanoDelta.(right)| left <= right

	## Whether the first coordinate is greater than the second.
	is_gt : PosixNanoDelta, PosixNanoDelta -> Bool
	is_gt = |PosixNanoDelta.(left), PosixNanoDelta.(right)| left > right

	## Whether the first coordinate is greater than or equal to the second.
	is_gte : PosixNanoDelta, PosixNanoDelta -> Bool
	is_gte = |PosixNanoDelta.(left), PosixNanoDelta.(right)| left >= right

	## Show the exact signed nanosecond count for diagnostics.
	to_inspect : PosixNanoDelta -> Str
	to_inspect = |PosixNanoDelta.(value)| "PosixNanoDelta(${value.to_str()} nanoseconds)"

	## Nanoseconds immediately before the epoch round downward to -1 microsecond.
	expect to_delta_with_rounding(from_nanoseconds(-1), Floor) == Ok(PosixDelta.from_microseconds(-1))

	## The largest microsecond value cannot be widened into I64 nanoseconds.
	expect from_delta(PosixDelta.from_microseconds(I64.highest)) == Err(OutOfRange)
}
