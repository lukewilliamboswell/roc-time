import PosixDelta

## Exact POSIX coordinates: microseconds since 1970-01-01T00:00:00Z.
## Leap seconds are not representable on this axis.
##
## Example
##
## Use integer microseconds for exact coordinates, or explicitly select the
## rounding policy when accepting decimal seconds. Zero is the Unix epoch; this
## coordinate does not attach a display timezone.
##
## ```roc
## import time.PosixBoundary
##
## expect {
##     point = PosixBoundary.from_seconds(1.25, RejectSubmicrosecond)?
##     PosixBoundary.to_microseconds(point) == 1250000
## }
## ```
##
## Examples assume a package dependency named `time`.
PosixBoundary :: [Micros(I64)].{

	## Precision reduction policy. RejectSubmicrosecond rejects inexact input;
	## Floor rounds toward negative infinity, Ceiling toward positive infinity,
	## and TowardZero discards the fractional part. NearestTiesEven chooses the
	## closest microsecond, resolving exact ties to the even microsecond.
	Rounding : [RejectSubmicrosecond, Floor, Ceiling, TowardZero, NearestTiesEven]

	## Construct an exact position from signed microseconds since the POSIX epoch,
	## 1970-01-01T00:00:00Z. Every I64 value is accepted; leap seconds are not distinct.
	from_microseconds : I64 -> PosixBoundary
	from_microseconds = |value| Micros(value)

	## Read the signed microsecond count since the POSIX epoch.
	to_microseconds : PosixBoundary -> I64
	to_microseconds = |Micros(value)| value

	## Convert nanoseconds since the POSIX epoch without losing precision.
	## Return Submicrosecond unless divisible by 1000, or OutOfRange if the result
	## cannot fit the supported I64 microsecond range.
	from_nanoseconds : I128 -> Try(PosixBoundary, [Submicrosecond, OutOfRange, ..])
	from_nanoseconds = |value| {
		from_nanoseconds_with_rounding(value, RejectSubmicrosecond)
	}

	## Convert nanoseconds since the POSIX epoch using the supplied rounding policy.
	## Range is checked after rounding; RejectSubmicrosecond rejects an inexact input.
	from_nanoseconds_with_rounding : I128, Rounding -> Try(PosixBoundary, [Submicrosecond, OutOfRange, ..])
	from_nanoseconds_with_rounding = |value, policy| {
		Ok(Micros(quantize(value, 1000, policy)?))
	}

	## Convert exact decimal seconds since the POSIX epoch with explicit rounding.
	## RejectSubmicrosecond preserves exactness; a rounded result outside I64
	## microseconds returns OutOfRange.
	from_seconds : Dec, Rounding -> Try(PosixBoundary, [Submicrosecond, OutOfRange, ..])
	from_seconds = |value, policy| {
		Ok(Micros(quantize(Dec.to_attos(value), 1000000000000, policy)?))
	}

	## Compare exact POSIX positions, returning LT, EQ or GT.
	compare : PosixBoundary, PosixBoundary -> [LT, EQ, GT]
	compare = |Micros(a), Micros(b)| {
		if a < b {
			LT
		} else if a > b {
			GT
		} else {
			EQ
		}
	}

	## Whether the first of two POSIX positions precedes the second in their numeric order.
	is_lt : PosixBoundary, PosixBoundary -> Bool
	is_lt = |Micros(a), Micros(b)| a < b

	## Whether the first of two POSIX positions precedes or equals the second.
	is_lte : PosixBoundary, PosixBoundary -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b

	## Whether the first of two POSIX positions follows the second in their numeric order.
	is_gt : PosixBoundary, PosixBoundary -> Bool
	is_gt = |Micros(a), Micros(b)| a > b

	## Whether the first of two POSIX positions follows or equals the second.
	is_gte : PosixBoundary, PosixBoundary -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b

	## Hash POSIX positions consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : PosixBoundary, Hasher -> Hasher
	to_hash = |Micros(value), hasher| value.to_hash(hasher)

	## Return a concise diagnostic description of these POSIX positions.
	## Use explicit conversions or text serialization when storing or exchanging data.
	to_inspect : PosixBoundary -> Str
	to_inspect = |Micros(value)| "PosixBoundary(${value.to_str()} microseconds)"

	## Equality of POSIX positions; values of other temporal domains must be converted explicitly.
	is_eq : PosixBoundary, PosixBoundary -> Bool
	is_eq = |Micros(a), Micros(b)| a == b

	## Add a signed POSIX displacement to a position. Return OutOfRange on overflow.
	## For calendar-day or month changes, use calendar arithmetic with an explicit context.
	shift : PosixBoundary, PosixDelta -> Try(PosixBoundary, [OutOfRange, ..])
	shift = |Micros(value), delta| {
		match I64.plus_try(value, PosixDelta.to_microseconds(delta)) {
			Ok(result) => Ok(Micros(result))
			Err(Overflow) => Err(OutOfRange)
		}
	}

	## Return the first position minus the second, as a signed POSIX displacement.
	## OutOfRange is possible even when both positions individually fit.
	## This is coordinate width, not leap-aware physical elapsed time.
	difference : PosixBoundary, PosixBoundary -> Try(PosixDelta, [OutOfRange, ..])
	difference = |Micros(a), Micros(b)| {
		match I64.minus_try(a, b) {
			Ok(result) => Ok(PosixDelta.from_microseconds(result))
			Err(Overflow) => Err(OutOfRange)
		}
	}

	expect shift(from_microseconds(9223372036854775807), PosixDelta.from_microseconds(1)) == Err(OutOfRange)
	expect shift(from_microseconds(-9223372036854775808), PosixDelta.from_microseconds(-1)) == Err(OutOfRange)
	expect difference(from_microseconds(9223372036854775807), from_microseconds(-1)) == Err(OutOfRange)
	expect difference(from_microseconds(-1), from_microseconds(1)) == Ok(PosixDelta.from_microseconds(-2))

	expect from_seconds(0.000001.Dec, RejectSubmicrosecond) == Ok(from_microseconds(1))
	expect from_seconds(-0.000001.Dec, RejectSubmicrosecond) == Ok(from_microseconds(-1))
	expect from_seconds(0.0000001.Dec, RejectSubmicrosecond) == Err(Submicrosecond)
	expect from_nanoseconds(-1) == Err(Submicrosecond)
	expect from_nanoseconds(-9223372036854775808000) == Ok(from_microseconds(-9223372036854775808))
	expect from_nanoseconds(9223372036854775807000) == Ok(from_microseconds(9223372036854775807))
	expect from_nanoseconds(9223372036854775808000) == Err(OutOfRange)
	expect from_nanoseconds(-9223372036854775809000) == Err(OutOfRange)

	# A nearest-point oracle over a finite lattice, independent of quotient rounding.
	expect {
		var $valid = Bool.True
		for n in [-2501.I128, -2500, -2499, -1500, -501, -500, -499, -1, 0, 1, 499, 500, 501, 1500, 2499, 2500, 2501] {
			var $best = -4.I64
			var $distance = 10000.I128
			for candidate in [-4.I64, -3, -2, -1, 0, 1, 2, 3, 4] {
				delta = I64.to_i128(candidate) * 1000 - n
				d = if delta < 0 {
					-delta
				} else {
					delta
				}
				if d < $distance or (d == $distance and I64.rem_by(candidate, 2) == 0) {
					$best = candidate
					$distance = d
				}
			}
			$valid = $valid and from_nanoseconds_with_rounding(n, NearestTiesEven) == Ok(from_microseconds($best))
		}
		$valid
	}

	expect from_seconds(-0.0000001.Dec, Floor) == Ok(from_microseconds(-1))
	expect from_seconds(-0.0000001.Dec, Ceiling) == Ok(from_microseconds(0))
	expect from_seconds(-0.0000009.Dec, TowardZero) == Ok(from_microseconds(0))
	expect from_seconds(0.0000001.Dec, Ceiling) == Ok(from_microseconds(1))
	expect from_nanoseconds_with_rounding(9223372036854775807499, NearestTiesEven) == Ok(from_microseconds(9223372036854775807))
	expect from_nanoseconds_with_rounding(9223372036854775807500, NearestTiesEven) == Err(OutOfRange)
	expect from_nanoseconds_with_rounding(-9223372036854775808500, NearestTiesEven) == Ok(from_microseconds(-9223372036854775808))
	expect from_nanoseconds_with_rounding(-9223372036854775808501, NearestTiesEven) == Err(OutOfRange)
	expect from_nanoseconds_with_rounding(I128.lowest, Floor) == Err(OutOfRange)
	expect from_nanoseconds_with_rounding(I128.highest, Ceiling) == Err(OutOfRange)
}

# Private: divisor is either 1000 or 10^12. Remainder magnitude is below divisor;
# quotient +/- 1 and twice the remainder cannot overflow I128. Narrow only last.
quantize : I128, I128, PosixBoundary.Rounding -> Try(I64, [Submicrosecond, OutOfRange, ..])
quantize = |value, divisor, policy| {
	q = I128.div_trunc_by(value, divisor)
	r = I128.rem_by(value, divisor)
	if r == 0 {
		return I128.to_i64_try(q)
	}
	rounded = match policy {
		RejectSubmicrosecond => return Err(Submicrosecond)
		TowardZero => q
		Floor => if r < 0 {
			q - 1
		} else {
			q
		}
		Ceiling => if r > 0 {
			q + 1
		} else {
			q
		}
		NearestTiesEven => {
			magnitude = if r < 0 {
				-r
			} else {
				r
			}
			if magnitude * 2 > divisor or (magnitude * 2 == divisor and I128.rem_by(q, 2) != 0) {
				q + if r < 0 {
					-1
				} else {
					1
				}
			} else {
				q
			}
		}
	}
	I128.to_i64_try(rounded)
}
