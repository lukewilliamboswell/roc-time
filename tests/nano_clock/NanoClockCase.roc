import fuzz.Fuzz
import time.ClockTime
import time.NanoClockTime

# R01/R02/R14: nanosecond clock positions, malformed numeric positions and the
# explicit narrowing to microsecond ClockTime.
NanoClockCase := { number : I64 }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(NanoClockCase)
	generator_for = |_| Fuzz.map(Fuzz.u64_in(0, 86400000000001), |number| { number: number.to_i64_wrap() - 1 })

	check : NanoClockCase -> Fuzz.Outcome
	check = |input| {
		if input.number < 0 or input.number >= 86400000000000 {
			if NanoClockTime.from_nanoseconds_since_midnight(input.number) != Err(OutOfRange) {
				crash "nanosecond clock range accepted"
			}
			return Fuzz.keep
		}
		# Uniform input rarely lands on a whole microsecond or a rounding tie,
		# so each case also checks those two neighbours.
		remainder = I64.rem_by(input.number, 1000)
		for number in [input.number, input.number - remainder, input.number - remainder + 500] {
			check_position(number)
		}
		Fuzz.keep
	}
}

check_position : I64 -> {}
check_position = |number| {
	value = match NanoClockTime.from_nanoseconds_since_midnight(number) {
		Ok(clock) => clock
		Err(_) => crash "valid nanosecond clock rejected"
	}
	if NanoClockTime.to_nanoseconds_since_midnight(value) != number or
		NanoClockTime.from_fields(NanoClockTime.to_fields(value)) != Ok(value) {
		crash "nanosecond clock round trip"
	}
	# Independent text oracle: decimal digits of the numeric coordinate,
	# assembled as ASCII bytes without production field or output helpers.
	h = I64.div_trunc_by(number, 3600000000000)
	m = I64.rem_by(I64.div_trunc_by(number, 60000000000), 60)
	s = I64.rem_by(I64.div_trunc_by(number, 1000000000), 60)
	base = [
		(48 + I64.div_trunc_by(h, 10)).to_u8_wrap(),
		(48 + I64.rem_by(h, 10)).to_u8_wrap(),
		58,
		(48 + I64.div_trunc_by(m, 10)).to_u8_wrap(),
		(48 + I64.rem_by(m, 10)).to_u8_wrap(),
		58,
		(48 + I64.div_trunc_by(s, 10)).to_u8_wrap(),
		(48 + I64.rem_by(s, 10)).to_u8_wrap(),
	]
	var $shortest = base
	var $full = base.append(46)
	var $remainder = I64.rem_by(number, 1000000000)
	var $divisor = 100000000.I64
	if $remainder != 0 {
		$shortest = $shortest.append(46)
	}
	while $divisor != 0 {
		digit = (48 + I64.div_trunc_by($remainder, $divisor)).to_u8_wrap()
		$full = $full.append(digit)
		if $remainder != 0 {
			$shortest = $shortest.append(digit)
		}
		$remainder = I64.rem_by($remainder, $divisor)
		$divisor = I64.div_trunc_by($divisor, 10)
	}
	expected_text = Str.from_utf8_lossy($shortest)
	full_text = Str.from_utf8_lossy($full)
	if NanoClockTime.to_text(value) != expected_text or NanoClockTime.parse(expected_text) != Ok(value) or
		NanoClockTime.parse(full_text) != Ok(value) {
		crash "nanosecond clock text differs from decimal coordinate model"
	}
	if NanoClockTime.parse("${full_text}0") != Err(UnsupportedPrecision) or
		NanoClockTime.parse("${expected_text}Z") != Err(Malformed) {
		crash "nanosecond clock accepted a tenth digit or an offset tail"
	}
	# Independent rounding oracle: integer quotient and remainder by 1000,
	# with each policy written out, then the ClockTime range check.
	quotient = I64.div_trunc_by(number, 1000)
	rest = I64.rem_by(number, 1000)
	up = if rest == 0 {
		quotient
	} else {
		quotient + 1
	}
	nearest = if rest < 500 {
		quotient
	} else if rest > 500 {
		quotient + 1
	} else if I64.rem_by(quotient, 2) == 0 {
		quotient
	} else {
		quotient + 1
	}
	exact = if rest == 0 {
		ClockTime.from_microseconds_since_midnight(quotient)
	} else {
		Err(Submicrosecond)
	}
	if NanoClockTime.to_clock_with_rounding(value, Floor) != ClockTime.from_microseconds_since_midnight(quotient) or
		NanoClockTime.to_clock_with_rounding(value, TowardZero) != ClockTime.from_microseconds_since_midnight(quotient) or
			NanoClockTime.to_clock_with_rounding(value, Ceiling) != ClockTime.from_microseconds_since_midnight(up) or
				NanoClockTime.to_clock_with_rounding(value, NearestTiesEven) != ClockTime.from_microseconds_since_midnight(nearest) or
					NanoClockTime.to_clock_with_rounding(value, RejectSubmicrosecond) != exact {
		crash "nanosecond clock rounding differs from integer model"
	}
	parts = NanoClockTime.split_microseconds(value)
	if ClockTime.to_microseconds_since_midnight(parts.clock) != quotient or parts.nanosecond.to_i64() != rest {
		crash "nanosecond clock split differs from integer model"
	}
	widened = NanoClockTime.from_clock(parts.clock)
	if !(widened <= value) or (widened == value) != (rest == 0) {
		crash "widened floor clock is not at or before the value"
	}
	if rest == 0 and NanoClockTime.to_text(value) != ClockTime.to_text(parts.clock) {
		crash "aligned nanosecond clock text differs from microsecond text"
	}
	if number < 86399999999999 {
		next = match NanoClockTime.from_nanoseconds_since_midnight(number + 1) {
			Ok(clock) => clock
			Err(_) => crash "next nanosecond clock rejected"
		}
		if !(value < next) or value == next {
			crash "nanosecond clock precision lost"
		}
	}
	{}
}
