import time.RfcDateTime
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
		# R02/R14: independent epoch-day clock grid, including the preceding
		# day. The parser receives text, never the expected coordinate.
		seconds = I64.mod_by(input.seconds.to_i64(), 86400)
		hour = seconds // 3600
		minute = I64.mod_by(seconds // 60, 60)
		second = I64.mod_by(seconds, 60)
		date_text = if input.number < 0 {
			"19691231"
		} else {
			"19700101"
		}
		text = "${date_text}T${two(hour)}${two(minute)}${two(second)}"
		parsed = match RfcDateTime.parse("${text}Z") {
			Ok(value) => value
			Err(_) => crash "valid epoch grid text rejected"
		}
		parsed_local = match RfcDateTime.parse(text) {
			Ok(value) => value
			Err(_) => crash "valid local grid text rejected"
		}
		expected_micros = (
			seconds - (
				if input.number < 0 {
					86400
				} else {
					0
				}
			)
		) * 1000000
		if RfcDateTime.utc_boundary(parsed) != Ok(PosixBoundary.from_microseconds(expected_micros)) or RfcDateTime.utc_boundary(parsed_local) != Err(NeedsContext) or parsed == parsed_local or RfcDateTime.parse(RfcDateTime.to_text(parsed)) != Ok(parsed) or RfcDateTime.parse("${text}+0000") != Err(Malformed) {
			crash "RFC value differs from epoch grid or lost UTC/local form"
		}
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

two : I64 -> Str
two = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
