import fuzz.Fuzz
import time.PosixBoundary
import time.PosixDelta

# R01. Full-range signed input with deliberate limit/zero bias. I128 is an
# independent reference for checked I64 arithmetic, never production storage.
endpoint = Fuzz.map2(
	Fuzz.u8_in(0, 7),
	Fuzz.u64,
	|choice, raw| {
		match choice {
			0 => I64.lowest
			1 => I64.highest
			2 => -1.I64
			3 => 0.I64
			4 => 1.I64
			_ => U64.to_i64_wrap(raw)
		}
	},
)

PrecisionCase := { a : I64, b : I64, nanos : U64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(PrecisionCase)
	generator_for = |_| { a: endpoint, b: endpoint, nanos: Fuzz.u64_in(0, 2000) }.Fuzz

	check : PrecisionCase -> Fuzz.Outcome
	check = |input| {
		a = PosixBoundary.from_microseconds(input.a)
		b = PosixBoundary.from_microseconds(input.b)
		if (a < b) != (input.a < input.b) or (a <= b) != (input.a <= input.b) or
			(a > b) != (input.a > input.b) or (a >= b) != (input.a >= input.b) {
			crash "R02 boundary operator dispatch differs from coordinate oracle"
		}
		if Dict.get(Dict.insert(Dict.empty(), a, 1.U64), PosixBoundary.from_microseconds(input.a)) != Ok(1) {
			crash "R02 equal boundary cannot retrieve dictionary entry"
		}
		aligned_nanos = I64.to_i128(input.a) * 1000
		if PosixBoundary.from_nanoseconds(aligned_nanos) != Ok(a) or
			PosixBoundary.from_nanoseconds(aligned_nanos + 1) != Err(Submicrosecond) {
			crash "R01 exact conversion or precision rejection failed"
		}
		sum = I64.to_i128(input.a) + I64.to_i128(input.b)
		difference = I64.to_i128(input.a) - I64.to_i128(input.b)
		expected_sum = match I128.to_i64_try(sum) {
			Ok(value) => Ok(PosixBoundary.from_microseconds(value))
			Err(OutOfRange) => Err(OutOfRange)
		}
		expected_difference = match I128.to_i64_try(difference) {
			Ok(value) => Ok(PosixDelta.from_microseconds(value))
			Err(OutOfRange) => Err(OutOfRange)
		}
		if PosixBoundary.shift(a, PosixDelta.from_microseconds(input.b)) != expected_sum {
			crash "R01 checked shift differs from I128 oracle"
		}
		if PosixBoundary.difference(a, b) != expected_difference {
			crash "R01 checked difference differs from I128 oracle"
		}
		nanoseconds = I64.to_i128(input.a) * 1000 + U64.to_i128(input.nanos) - 1000
		exact = PosixBoundary.from_nanoseconds(nanoseconds)
		seconds = Dec.from_attos(nanoseconds * 1000000000)
		if PosixBoundary.from_seconds(seconds, RejectSubmicrosecond) != exact {
			crash "R01 Dec seconds and nanoseconds disagree"
		}
		if I128.rem_by(nanoseconds, 1000) == 0 {
			expected = match I128.to_i64_try(I128.div_trunc_by(nanoseconds, 1000)) {
				Ok(value) => Ok(PosixBoundary.from_microseconds(value))
				Err(OutOfRange) => Err(OutOfRange)
			}
			if exact != expected {
				crash "R01 aligned conversion differs from exact oracle"
			}
		} else if exact != Err(Submicrosecond) {
			crash "R01 implicit precision loss"
		}

		# Bound the nearest rounding error and require an even result at a tie.
		if PosixBoundary.from_seconds(seconds, NearestTiesEven) != PosixBoundary.from_nanoseconds_with_rounding(nanoseconds, NearestTiesEven) {
			crash "R01 Dec nearest rounding and nanoseconds disagree"
		}
		match PosixBoundary.from_nanoseconds_with_rounding(nanoseconds, NearestTiesEven) {
			Ok(value) => {
				micros = PosixBoundary.to_microseconds(value)
				error = I64.to_i128(micros) * 1000 - nanoseconds
				if error < -500 or error > 500 {
					crash "R01 nearest rounding error"
				}
				if (error == -500 or error == 500) and I64.rem_by(micros, 2) != 0 {
					crash "R01 nearest tie is not even"
				}
			}
			Err(OutOfRange) => {
				# Upper limit is odd, lower limit even; ties differ at the extremes.
				if nanoseconds >= I64.to_i128(I64.lowest) * 1000 - 500 and
					nanoseconds < I64.to_i128(I64.highest) * 1000 + 500 {
					crash "R01 spurious rounding overflow"
				}
			}
			Err(Submicrosecond) => crash "R01 explicit nearest rounding rejected precision"
		}
		Fuzz.keep
	}
}
