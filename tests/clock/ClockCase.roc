import fuzz.Fuzz
import time.ClockTime
import time.ClockPattern

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
			# Independent text oracle: decimal digit positions from the numeric
			# coordinate, assembled as ASCII bytes without production field/output
			# helpers. R01/R14: exact full-day domain, shortest decimal precision.
			h = I64.div_trunc_by(input.number, 3600000000)
			m = I64.rem_by(I64.div_trunc_by(input.number, 60000000), 60)
			s = I64.rem_by(I64.div_trunc_by(input.number, 1000000), 60)
			var $bytes = [
				(48 + I64.div_trunc_by(h, 10)).to_u8_wrap(),
				(48 + I64.rem_by(h, 10)).to_u8_wrap(),
				58,
				(48 + I64.div_trunc_by(m, 10)).to_u8_wrap(),
				(48 + I64.rem_by(m, 10)).to_u8_wrap(),
				58,
				(48 + I64.div_trunc_by(s, 10)).to_u8_wrap(),
				(48 + I64.rem_by(s, 10)).to_u8_wrap(),
			]
			var $remainder = I64.rem_by(input.number, 1000000)
			if $remainder != 0 {
				$bytes = $bytes.append(46)
				var $divisor = 100000.I64
				while $remainder != 0 {
					$bytes = $bytes.append((48 + I64.div_trunc_by($remainder, $divisor)).to_u8_wrap())
					$remainder = I64.rem_by($remainder, $divisor)
					$divisor = I64.div_trunc_by($divisor, 10)
				}
			}
			expected_text = Str.from_utf8_lossy($bytes)
			shared_text = [expected_text, expected_text]
			if ClockTime.to_text(value) != expected_text or ClockTime.parse(expected_text) != Ok(value) {
				crash "clock text differs from decimal coordinate model"
			}
			for text in shared_text {
				if ClockTime.parse(text) != Ok(value) {
					crash "shared clock text differs"
				}
				if ClockTime.parse("${text}Z") != Err(Malformed) {
					crash "clock accepted offset tail"
				}
			}
			minute_text = Str.from_utf8_lossy($bytes.take_first(5))
			match ClockTime.parse(minute_text) {
				Ok(parsed) => if ClockTime.to_microseconds_since_midnight(parsed) != input.number - I64.rem_by(input.number, 60000000) {
					crash "omitted seconds meaning"
				}
				Err(_) => crash "native minute label rejected"
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
			hour = ClockTime.to_fields(value).hour
			pattern = match ClockPattern.new(value, { hours: [23, hour, 0, hour], minutes: [], seconds: [59, 0, 59] }) {
				Ok(found) => found
				Err(_) => crash "clock pattern"
			}
			# Independent coordinate arithmetic for the selected hour/second grid.
			var $expected = []
			minute_part = I64.rem_by(I64.div_trunc_by(input.number, 60000000), 60) * 60000000
			fraction = I64.rem_by(input.number, 1000000)
			var $candidate_hour = 0.I64
			while $candidate_hour < 24 {
				if $candidate_hour == 0 or $candidate_hour == hour.to_i64() or $candidate_hour == 23 {
					for second in [0.I64, 59] {
						$expected = $expected.append($candidate_hour * 3600000000 + minute_part + second * 1000000 + fraction)
					}
				}
				$candidate_hour = $candidate_hour + 1
			}
			var $observed = []
			for clock in pattern {
				indexed = match ClockPattern.at(pattern, $observed.len()) {
					Ok(found) => found
					Err(_) => crash "clock index"
				}
				if indexed != clock {
					crash "clock iterator differs from indexed access"
				}
				$observed = $observed.append(ClockTime.to_microseconds_since_midnight(clock))
			}
			if $observed != $expected or ClockPattern.count(pattern) != $expected.len() {
				crash "clock candidates differ from coordinate grid"
			}
		}
		Fuzz.keep
	}
}
