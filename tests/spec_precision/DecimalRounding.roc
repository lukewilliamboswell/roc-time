import fuzz.Solve
import time.PosixBoundary

DecimalRounding := [].{}

attos_per_nanosecond = 1_000_000_000.U64

attos_per_microsecond = 1_000_000_000_000.U64

lowest_attos = I64.lowest.to_i128() * attos_per_microsecond.to_i128()

highest_attos = I64.highest.to_i128() * attos_per_microsecond.to_i128()

round_attos = |value, policy| PosixBoundary.from_seconds(Dec.from_attos(value), policy).map_ok(PosixBoundary.to_microseconds)

# A caller importing Dec seconds must retain the original attoseconds
# until rounding is complete. Search the full microsecond below I64.lowest
# for the closest input that would be accepted after truncating to nanoseconds.
# The distance to the outside neighbor is one microsecond minus the distance
# to I64.lowest. At equal distance the inside (lowest) neighbor is even.
expect {
	witness = Solve.find_near_within(
		{ nanoseconds: Solve.u64_in(0, 999), fraction: Solve.u64_in(0, attos_per_nanosecond - 1) }.Solve,
		|{ nanoseconds, fraction }| {
			width = Solve.Uint.from_u64(attos_per_microsecond)
			truncated = nanoseconds * Solve.Uint.from_u64(attos_per_nanosecond)
			exact = truncated + fraction
			Solve.all([exact.gt(width - exact), truncated.lte(width - truncated)])
		},
		[0, 0],
		1000,
	)?
	match witness {
		Found({ nanoseconds, fraction }) => {
			nanos = nanoseconds.value()
			attos = fraction.value()
			midpoint = lowest_attos - nanos.to_i128() * attos_per_nanosecond.to_i128()
			nanos == 500 and attos == 1 and
				round_attos(midpoint, NearestTiesEven) == Ok(I64.lowest) and
					round_attos(midpoint - attos.to_i128(), NearestTiesEven) == Err(OutOfRange) and
						round_attos(midpoint + 1, NearestTiesEven) == Ok(I64.lowest)
		}
		_ => Bool.False
	}
}

# At the upper midpoint the even neighbor lies outside the carrier. An
# attosecond closer to I64.highest changes the result from overflow to success.
expect {
	midpoint = highest_attos + (attos_per_microsecond.to_i128() // 2)
	round_attos(midpoint - 1, NearestTiesEven) == Ok(I64.highest) and
		round_attos(midpoint, NearestTiesEven) == Err(OutOfRange) and
			round_attos(midpoint + 1, NearestTiesEven) == Err(OutOfRange)
}

# At both signed extremes, one extra attosecond affects the directed policies
# and the exact policy. The range error depends on the rounded microsecond.
expect {
	below = lowest_attos - 1
	above = highest_attos + 1
	policies = [RejectSubmicrosecond, Floor, Ceiling, TowardZero]
	policies.map(|policy| round_attos(below, policy)) == [Err(Submicrosecond), Err(OutOfRange), Ok(I64.lowest), Ok(I64.lowest)] and
		policies.map(|policy| round_attos(above, policy)) == [Err(Submicrosecond), Ok(I64.highest), Err(OutOfRange), Ok(I64.highest)]
}
