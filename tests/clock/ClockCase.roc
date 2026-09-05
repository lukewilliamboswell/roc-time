import fuzz.Fuzz
import time.ClockTime

# R01/R07/R08: local microsecond positions and malformed numeric positions.
ClockCase := { number : I64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(ClockCase)
	generator_for = |_| Fuzz.map(Fuzz.u64_in(0, 86400000001), |number| { number: number.to_i64_wrap() - 1 })

	check : ClockCase -> Fuzz.Outcome
	check = |input| {
		result = ClockTime.from_microseconds_since_midnight(input.number)
		if input.number < 0 or input.number >= 86400000000 {
			if result != Err(OutOfRange) {
				crash "clock range accepted"
			}
		} else {
			value = match result {
				Ok(clock) => clock
				Err(_) => crash "valid clock rejected"
			}
			if ClockTime.to_microseconds_since_midnight(value) != input.number or
				ClockTime.from_fields(ClockTime.to_fields(value)) != Ok(value) {
				crash "clock round trip"
			}
			if input.number < 86399999999 {
				next = match ClockTime.from_microseconds_since_midnight(input.number + 1) {
					Ok(clock) => clock
					Err(_) => crash "next clock rejected"
				}
				if !(value < next) or value == next {
					crash "clock precision lost"
				}
			}
		}
		Fuzz.keep
	}
}
