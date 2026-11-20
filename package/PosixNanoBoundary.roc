import PosixBoundary
import MicrosecondRounding
import Quantize
import PosixNanoDelta

## Signed POSIX epoch position in whole nanoseconds.
PosixNanoBoundary :: I64.{

	## Construct from any signed I64 nanosecond count.
	from_nanoseconds : I64 -> PosixNanoBoundary
	from_nanoseconds = |value| PosixNanoBoundary.(value)

	## Read the exact signed nanosecond count.
	to_nanoseconds : PosixNanoBoundary -> I64
	to_nanoseconds = |PosixNanoBoundary.(value)| value

	## Convert a microsecond value when its scaled count fits I64.
	from_boundary : PosixBoundary -> Try(PosixNanoBoundary, [OutOfRange])
	from_boundary = |value| {
		count = value.to_microseconds().times_try(1000) ? |_| OutOfRange
		Ok(from_nanoseconds(count))
	}

	## Convert exactly to the microsecond domain, rejecting fractional microseconds.
	to_boundary : PosixNanoBoundary -> Try(PosixBoundary, [Submicrosecond])
	to_boundary = |value| value.to_boundary_with_rounding(RejectSubmicrosecond)

	## Convert to the microsecond domain using the supplied rounding policy.
	to_boundary_with_rounding : PosixNanoBoundary, MicrosecondRounding -> Try(PosixBoundary, [Submicrosecond])
	to_boundary_with_rounding = |PosixNanoBoundary.(value), rounding| {
		result = Quantize.to_microseconds({ value, divisor: 1000, rounding })?
		Ok(PosixBoundary.from_microseconds(result))
	}

	## Compare exact signed nanosecond counts within this domain.
	is_eq : _

	## Hash the signed nanosecond count consistently with equality.
	to_hash : _

	## Order by signed nanosecond count.
	order_relative_to : PosixNanoBoundary, PosixNanoBoundary -> [Before, Same, After]
	order_relative_to = |PosixNanoBoundary.(left), PosixNanoBoundary.(right)| left.order_relative_to(right)

	## Whether the first coordinate is less than the second.
	is_lt : PosixNanoBoundary, PosixNanoBoundary -> Bool
	is_lt = |PosixNanoBoundary.(left), PosixNanoBoundary.(right)| left < right

	## Whether the first coordinate is less than or equal to the second.
	is_lte : PosixNanoBoundary, PosixNanoBoundary -> Bool
	is_lte = |PosixNanoBoundary.(left), PosixNanoBoundary.(right)| left <= right

	## Whether the first coordinate is greater than the second.
	is_gt : PosixNanoBoundary, PosixNanoBoundary -> Bool
	is_gt = |PosixNanoBoundary.(left), PosixNanoBoundary.(right)| left > right

	## Whether the first coordinate is greater than or equal to the second.
	is_gte : PosixNanoBoundary, PosixNanoBoundary -> Bool
	is_gte = |PosixNanoBoundary.(left), PosixNanoBoundary.(right)| left >= right

	## Show the exact signed nanosecond count for diagnostics.
	to_inspect : PosixNanoBoundary -> Str
	to_inspect = |PosixNanoBoundary.(value)| "PosixNanoBoundary(${value.to_str()} nanoseconds)"

	## Add a nanosecond coordinate displacement with checked arithmetic.
	shift : PosixNanoBoundary, PosixNanoDelta -> Try(PosixNanoBoundary, [OutOfRange])
	shift = |PosixNanoBoundary.(value), delta| {
		result = value.plus_try(delta.to_nanoseconds()) ? |_| OutOfRange
		Ok(from_nanoseconds(result))
	}

	## Subtract the right position from the left position.
	difference : { left : PosixNanoBoundary, right : PosixNanoBoundary } -> Try(PosixNanoDelta, [OutOfRange])
	difference = |{ left: PosixNanoBoundary.(left), right: PosixNanoBoundary.(right) }| {
		result = left.minus_try(right) ? |_| OutOfRange
		Ok(PosixNanoDelta.from_nanoseconds(result))
	}

	## Nanoseconds immediately before the epoch round downward to -1 microsecond.
	expect to_boundary_with_rounding(from_nanoseconds(-1), Floor) == Ok(PosixBoundary.from_microseconds(-1))

	## The largest microsecond value cannot be widened into I64 nanoseconds.
	expect from_boundary(PosixBoundary.from_microseconds(I64.highest)) == Err(OutOfRange)

	## Sorting and dictionary lookup use the exact scalar value.
	expect {
		early = from_nanoseconds(-1)
		late = from_nanoseconds(1)
		ordered = [late, early].sort()
		keys = Dict.empty().insert(early, "before epoch")
		ordered == [early, late] and keys.get(from_nanoseconds(-1)) == Ok("before epoch")
	}

	## Differences may overflow even when both operands fit.
	expect difference({ left: from_nanoseconds(I64.highest), right: from_nanoseconds(-1) }) == Err(OutOfRange)

}
