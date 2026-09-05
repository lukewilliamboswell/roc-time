import fuzz.Fuzz
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules

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

OffsetCase := { number : I64, seconds : I32 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(OffsetCase)
	generator_for = |_| { number: endpoint, seconds: Fuzz.map(Fuzz.u64, |n| n.to_i32_wrap()) }.Fuzz

	check : OffsetCase -> Fuzz.Outcome
	check = |input| {
		boundary = PosixBoundary.from_microseconds(input.number)
		offset = FixedOffset.from_seconds(input.seconds)
		span = rule_span(I64.lowest, I64.highest)
		rules = match ZoneRules.new(
			"Synthetic/Step",
			"v1",
			span,
			FixedOffset.from_seconds(0),
			[
				{ at: PosixBoundary.from_microseconds(0), offset },
			],
		) {
			Ok(value) => value
			Err(_) => crash "valid synthetic rules rejected"
		}
		expected_offset = if input.number == I64.highest {
			Err(OutsideValidity)
		} else if input.number < 0 {
			Ok(FixedOffset.from_seconds(0))
		} else {
			Ok(offset)
		}
		if ZoneRules.offset_at(rules, boundary) != expected_offset {
			crash "rule lookup disagrees with independent step function"
		}
		for calendar in [Gregorian, Julian] {
			local = match FixedOffset.project(offset, boundary, calendar) {
				Ok(value) => value
				Err(_) => crash "full POSIX range projection failed"
			}
			if FixedOffset.resolve(offset, local) != Ok(boundary) {
				crash "offset projection changed boundary"
			}
			# Resolving the same label with offset zero changes the coordinate
			# by exactly the explicit offset, including overflow outcomes.
			expected = match I128.to_i64_try(input.number.to_i128() + input.seconds.to_i128() * 1000000) {
				Ok(number) => Ok(PosixBoundary.from_microseconds(number))
				Err(_) => Err(OutOfRange)
			}
			if FixedOffset.resolve(FixedOffset.from_seconds(0), local) != expected {
				crash "offset sign or endpoint range incorrect"
			}
		}
		Fuzz.keep
	}
}

rule_span = |lower, upper| match PosixSpan.new(PosixBoundary.from_microseconds(lower), PosixBoundary.from_microseconds(upper)) {
	Ok(value) => value
	Err(_) => crash "valid synthetic rule range rejected"
}
