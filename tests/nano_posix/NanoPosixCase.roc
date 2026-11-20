import time.PosixBoundary
import time.PosixDelta
import time.PosixNanoBoundary
import time.PosixNanoDelta
import fuzz.Fuzz

NanoPosixCase := { number : I64 }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(NanoPosixCase)
	generator_for = |_| Fuzz.map(Fuzz.u64_in(0, U64.highest), |number| { number: number.to_i64_wrap() })
	check : NanoPosixCase -> Fuzz.Outcome
	check = |{ number }| {
		boundary = PosixNanoBoundary.from_nanoseconds(number)
		delta = PosixNanoDelta.from_nanoseconds(number)
		for adjustment in [-1001.I64, -1, 0, 1, 1001] {
			expected = (number.to_i128() + adjustment.to_i128()).to_i64_try().map_ok(PosixNanoBoundary.from_nanoseconds)
			if boundary.shift(PosixNanoDelta.from_nanoseconds(adjustment)) != expected {
				crash "POSIX nanosecond shift disagrees with widened arithmetic"
			}
			other = PosixNanoBoundary.from_nanoseconds(adjustment)
			expected_delta = (number.to_i128() - adjustment.to_i128()).to_i64_try().map_ok(PosixNanoDelta.from_nanoseconds)
			if PosixNanoBoundary.difference({ left: boundary, right: other }) != expected_delta {
				crash "POSIX nanosecond difference disagrees with widened arithmetic"
			}
		}
		# On this bounded microsecond lattice inspect both candidates and compare distances.
		floor = number // 1000 - if (number % 1000 < 0) 1 else 0
		ceiling = floor + if (number % 1000 != 0) 1 else 0
		floor_distance = number.to_i128() - floor.to_i128() * 1000
		ceiling_distance = ceiling.to_i128() * 1000 - number.to_i128()
		nearest = if (floor_distance < ceiling_distance or (floor_distance == ceiling_distance and floor % 2 == 0)) floor else ceiling
		for { policy, expected } in [
			{ policy: Floor, expected: Ok(floor) },
			{ policy: Ceiling, expected: Ok(ceiling) },
			{ policy: TowardZero, expected: Ok(number // 1000) },
			{ policy: NearestTiesEven, expected: Ok(nearest) },
			{ policy: RejectSubmicrosecond, expected: if (floor == ceiling) Ok(floor) else Err(Submicrosecond) },
		] {
			if boundary.to_boundary_with_rounding(policy).map_ok(PosixBoundary.to_microseconds) != expected or delta.to_delta_with_rounding(policy).map_ok(PosixDelta.to_microseconds) != expected {
				crash "POSIX nanosecond rounding disagrees with the lattice oracle"
			}
		}
		Fuzz.keep
	}
}
