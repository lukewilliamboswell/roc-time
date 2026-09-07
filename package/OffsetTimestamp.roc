import SemanticFact
import GregorianDate
import CalendarDate
import ClockTime
import LocalDateTime
import FixedOffset
import PosixBoundary

## Complete offset-bearing timestamps, rfc3339-microseconds-rfc9557-base-v1.
## RFC 3339 sections 5.6–5.8 with RFC 9557 section 2 offset semantics.
## Four-digit astronomical Gregorian years 0000–9999, required seconds and
## zero through six supplied fractional digits. This is an instant declaration,
## not a calendar selection of the supplied precision's width.
##
## Z and -00:00 both mean UTC is known without asserting a local offset;
## canonical output uses Z. Numeric +00:00 retains its assertion. Lowercase
## t/z are accepted and emitted uppercase. Fractional width is preserved:
## .12 and .120 denote the same position but are distinct declarations.
##
## Incomplete prefixes have valid completed fields; unfinished digit fields are
## checked syntactically. A trailing [ after a complete base timestamp recognizes
## excluded annotations without validating their grammar.
## Leap seconds, fractions beyond six digits and IXDTF annotations are explicitly
## unsupported. No rounding, zone lookup, implicit clock or full ISO claim.
## Parsing checks a 256-byte limit before streaming into scalar fields, without
## materializing a byte list. Construction, conversion and
## formatting have constant bounded work. Canonical standard text can be stored directly.
OffsetTimestamp :: { date : GregorianDate, clock : ClockTime, fraction_digits : U8, offset : Offset }.{
	Offset : [UnassertedUtc, Asserted(FixedOffset)]
	Parts : { date : GregorianDate, clock : ClockTime, fraction_digits : U8, offset : Offset }
	Error : [Malformed, Incomplete, InvalidDate, InvalidTime, InvalidOffset, OutOfRange, TooLarge, UnsupportedPrecision, UnsupportedLeapSecond, UnsupportedAnnotations]

	## Generic encodings carry canonical text, never the opaque backing record.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : OffsetTimestamp, rest : state }, [InvalidOffsetTimestamp(Error), Encoding(err), ..]))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
		]
	parser_for = |encoding| {
		Encoding : encoding
		|state| {
			parsed = match Encoding.parse_str(encoding, state) {
				Ok(value) => value
				Err(error) => return Err(Encoding(error))
			}
			match parse(parsed.value) {
				Ok(value) => Ok({ value, rest: parsed.rest })
				Err(error) => Err(InvalidOffsetTimestamp(error))
			}
		}
	}

	encoder_for : encoding -> (OffsetTimestamp, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(OffsetTimestamp, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid OffsetTimestamp literal: ${Str.inspect(error)}"))
	}

	profile : Str
	profile = "rfc3339-microseconds-rfc9557-base-v1"

	new : Parts -> Try(OffsetTimestamp, Error)
	new = |parts| {
		year = GregorianDate.to_fields(parts.date).year
		if year < 0 or year > 9999 {
			return Err(OutOfRange)
		}
		if parts.fraction_digits > 6 {
			return Err(UnsupportedPrecision)
		}
		unit = fraction_unit(parts.fraction_digits)
		if U32.rem_by(ClockTime.to_fields(parts.clock).microsecond, unit) != 0 {
			return Err(UnsupportedPrecision)
		}
		match parts.offset {
			UnassertedUtc => {}
			Asserted(offset) => {
				seconds = FixedOffset.to_seconds(offset)
				if seconds < -86340 or seconds > 86340 or I32.rem_by(seconds, 60) != 0 {
					return Err(InvalidOffset)
				}
			}
		}
		Ok({ date: parts.date, clock: parts.clock, fraction_digits: parts.fraction_digits, offset: parts.offset })
	}

	parts : OffsetTimestamp -> Parts
	parts = |value| { date: value.date, clock: value.clock, fraction_digits: value.fraction_digits, offset: value.offset }
	local_label : OffsetTimestamp -> LocalDateTime
	local_label = |value| LocalDateTime.new(CalendarDate.from_gregorian(value.date), value.clock)

	## This source label is UTC for UnassertedUtc and offset-local otherwise.
	boundary : OffsetTimestamp -> Try(PosixBoundary, [OutOfRange, ..])
	boundary = |value| FixedOffset.resolve(effective_offset(value.offset), local_label(value))

	## Explicit projection for canonical timestamp output. The requested width
	## must represent the position exactly; this operation never rounds.
	from_boundary : PosixBoundary, Offset, U8 -> Try(OffsetTimestamp, Error)
	from_boundary = |point, offset, fraction_digits| {
		if fraction_digits > 6 {
			return Err(UnsupportedPrecision)
		}
		match offset {
			UnassertedUtc => {}
			Asserted(fixed) => {
				seconds = FixedOffset.to_seconds(fixed)
				if seconds < -86340 or seconds > 86340 or I32.rem_by(seconds, 60) != 0 {
					return Err(InvalidOffset)
				}
			}
		}
		local = match FixedOffset.project(effective_offset(offset), point, Gregorian) {
			Ok(value) => value
			Err(_) => return Err(OutOfRange)
		}
		fields = CalendarDate.to_fields(LocalDateTime.date(local))
		date = match GregorianDate.from_fields(fields) {
			Ok(value) => value
			Err(_) => return Err(OutOfRange)
		}
		new({ date, clock: LocalDateTime.clock(local), fraction_digits, offset })
	}

	parse : Str -> Try(OffsetTimestamp, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 256 {
			return Err(TooLarge)
		}
		length = text.count_utf8_bytes()
		# Accumulate eight date digits and six clock digits separately in U32;
		# the existing date/time separator resets the accumulator.
		# Suffix syntax facts are deferred until fixed field and clock checks,
		# retaining the established error precedence even for incomplete input.
		# Defer malformed errors until after scanning so loop state stays scalar.
		var $bad = Bool.False
		var $index = 0.U64
		var $packed = 0.U32
		var $date_digits = 0.U32
		var $fraction_seen = Bool.False
		var $fractional = 0.U32
		var $count = 0.U8
		var $marker = None
		var $offset_count = 0.U8
		var $hours = 0.U32
		var $minutes = 0.U32
		var $offset_malformed = Bool.False
		var $trailing = None
		for byte in text.iter_utf8() {
			if $index < 19 {
				if $index == 4 or $index == 7 {
					if byte != 45 {
						$bad = Bool.True
						break
					}
				} else if $index == 10 {
					if byte != 84 and byte != 116 {
						$bad = Bool.True
						break
					}
					$date_digits = $packed
					$packed = 0
				} else if $index == 13 or $index == 16 {
					if byte != 58 {
						$bad = Bool.True
						break
					}
				} else {
					if !digit(byte) {
						$bad = Bool.True
						break
					}
					$packed = $packed * 10 + (byte - 48).to_u32()
				}
			} else {
				match $marker {
					None => {
						if $index == 19 and byte == 46 {
							$fraction_seen = Bool.True
						} else if $fraction_seen and digit(byte) {
							if $count < 6 {
								$fractional = $fractional * 10 + (byte - 48).to_u32()
							}
							if $count < 7 {
								$count = $count + 1
							}
						} else {
							$marker = Some(byte)
							$offset_count = 1
						}
					}
					Some(marker) => {
						if (marker == 43 or marker == 45) and $offset_count < 6 {
							if $offset_count == 3 {
								$offset_malformed = $offset_malformed or byte != 58
							}
								else if digit(byte) {
									if $offset_count < 3 {
										$hours = $hours * 10 + (byte - 48).to_u32()
									}
										else {
											$minutes = $minutes * 10 + (byte - 48).to_u32()
										}
								} else {
									$offset_malformed = Bool.True
								}
							$offset_count = $offset_count + 1
						} else {
							$trailing = Some(byte)
							break
						}
					}
				}
			}
			$index = $index + 1
		}
		if $bad {
			return Err(Malformed)
		}
		# Right-pad only incomplete prefixes, so complete earlier fields decode
		# identically. Punctuation positions do not contribute decimal digits.
		while $index < 19 {
			if $index == 10 {
				$date_digits = $packed
				$packed = 0
			} else if $index != 4 and $index != 7 and $index != 13 and $index != 16 {
				$packed = $packed * 10
			}
			$index = $index + 1
		}
		fields = { year: $date_digits // 10000, month: ($date_digits // 100) % 100, day: $date_digits % 100, hour: ($packed // 10000) % 100, minute: ($packed // 100) % 100, second: $packed % 100 }
		tail = { fraction_seen: $fraction_seen, fractional: $fractional, count: $count, marker: $marker, offset_count: $offset_count, hours: $hours, minutes: $minutes, offset_malformed: $offset_malformed, trailing: $trailing }
		if length >= 7 and (fields.month < 1 or fields.month > 12) {
			return Err(InvalidDate)
		}
		if length >= 13 and fields.hour > 23 {
			return Err(InvalidTime)
		}
		if length >= 16 and fields.minute > 59 {
			return Err(InvalidTime)
		}
		if length < 10 {
			return Err(Incomplete)
		}
		date = match GregorianDate.from_fields({ year: fields.year.to_i64(), month: fields.month.to_u8_wrap(), day: fields.day.to_u8_wrap() }) {
			Ok(value) => value
			Err(_) => return Err(InvalidDate)
		}
		if length < 19 {
			return Err(Incomplete)
		}

		if tail.fraction_seen and tail.count == 0 {
			return if tail.marker == None {
				Err(Incomplete)
			} else {
				Err(Malformed)
			}
		}
		clock_count = if tail.count > 6 {
			6.U8
		} else {
			tail.count
		}
		clock = match ClockTime.from_fields({ hour: fields.hour.to_u8_wrap(), minute: fields.minute.to_u8_wrap(), second: fields.second.to_u8_wrap(), microsecond: tail.fractional * fraction_unit(clock_count) }) {
			Ok(value) => value
			Err(UnsupportedLeapSecond) => return Err(UnsupportedLeapSecond)
			Err(_) => return Err(InvalidTime)
		}
		marker = match tail.marker {
			None => return Err(Incomplete)
			Some(value) => value
		}
		var $offset = UnassertedUtc
		if marker == 90 or marker == 122 {
			# UTC has no numeric fields.
		} else if marker == 43 or marker == 45 {
			if tail.offset_malformed {
				return Err(Malformed)
			}
			if tail.offset_count >= 3 and tail.hours > 23 {
				return Err(InvalidOffset)
			}
			if tail.offset_count < 6 {
				return Err(Incomplete)
			}
			if tail.minutes > 59 {
				return Err(InvalidOffset)
			}
			seconds = (tail.hours * 3600 + tail.minutes * 60).to_i32_wrap()
			if marker == 43 or seconds != 0 {
				$offset = Asserted(
					FixedOffset.from_seconds(
						if marker == 45 {
							-seconds
						} else {
							seconds
						},
					),
				)
			}
		} else {
			return Err(Malformed)
		}
		match tail.trailing {
			Some(91) => return Err(UnsupportedAnnotations)
			Some(_) => return Err(Malformed)
			None => {}
		}
		if tail.count > 6 {
			return Err(UnsupportedPrecision)
		}

		# The parser has already established every new invariant: four year
		# digits give 0..9999, nominal constructors validate date/clock, the
		# fraction is scaled to its supplied width (at most six), and numeric
		# offsets contain bounded hours/minutes, hence whole minutes within
		# +/-23:59. Preserve the validated fields without checking them twice.
		Ok({ date, clock, fraction_digits: tail.count, offset: $offset })
	}

	## Validated fields need at most 32 ASCII bytes: 19 fixed, 7 fractional,
	## and 6 for an asserted offset. Build one owned buffer rather than padded
	## temporary strings. Formatting preserves supplied width and offset intent.
	to_text : OffsetTimestamp -> Str
	to_text = |value| {
		date = GregorianDate.to_fields(value.date)
		clock = ClockTime.to_fields(value.clock)
		var $bytes = List.with_capacity(32)
		# new/parse prove the year is 0..9999; all other fields are validated
		# by their nominal constructors. These narrowings cannot lose precision.
		$bytes = append_decimal($bytes, date.year.to_u32_wrap(), 1000, 4)
		$bytes = append_decimal($bytes.append(45), date.month.to_u32(), 10, 2)
		$bytes = append_decimal($bytes.append(45), date.day.to_u32(), 10, 2)
		$bytes = append_decimal($bytes.append(84), clock.hour.to_u32(), 10, 2)
		$bytes = append_decimal($bytes.append(58), clock.minute.to_u32(), 10, 2)
		$bytes = append_decimal($bytes.append(58), clock.second.to_u32(), 10, 2)
		if value.fraction_digits > 0 {
			$bytes = append_decimal($bytes.append(46), clock.microsecond, 100000, value.fraction_digits)
		}
		match value.offset {
			UnassertedUtc => {
				$bytes = $bytes.append(90)
			}
			Asserted(fixed) => {
				seconds = FixedOffset.to_seconds(fixed)
				# The profile restricts offsets to +/-86340 whole seconds.
				absolute = if seconds < 0 {
					$bytes = $bytes.append(45)
					(-seconds).to_u32_wrap()
				} else {
					$bytes = $bytes.append(43)
					seconds.to_u32_wrap()
				}
				$bytes = append_decimal($bytes, U32.div_trunc_by(absolute, 3600), 10, 2)
				$bytes = append_decimal($bytes.append(58), U32.rem_by(U32.div_trunc_by(absolute, 60), 60), 10, 2)
			}
		}
		match Str.from_utf8($bytes) {
			Ok(text) => text
			Err(_) => crash "Timestamp formatter emits only ASCII digits and punctuation"
		}
	}

	is_eq : OffsetTimestamp, OffsetTimestamp -> Bool
	is_eq = |a, b| a.date == b.date and a.clock == b.clock and a.fraction_digits == b.fraction_digits and a.offset == b.offset
	to_hash : OffsetTimestamp, Hasher -> Hasher
	to_hash = |value, hasher| {
		state = value.fraction_digits.to_hash(value.clock.to_hash(value.date.to_hash(hasher)))
		match value.offset {
			UnassertedUtc => (0.U8).to_hash(state)
			Asserted(offset) => offset.to_hash((1.U8).to_hash(state))
		}
	}

	## One bounded semantic fact, retaining supplied decimal width and offset
	## assertion. Reading facts never resolves a zone or materializes coverage.
	fact_count : OffsetTimestamp -> U64
	fact_count = |_| 1
	fact_at : OffsetTimestamp, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| if index == 0 {
		Item(SemanticFact.new(TimestampDescription({ kind: OffsetTimestamp, local: local_label(value), fraction_digits: value.fraction_digits, offset: value.offset, zone_present: Bool.False, annotation_count: 0 })))
	} else {
		End
	}
	to_inspect : OffsetTimestamp -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "Timestamp has one semantic fact"
	}
}

fraction_unit = |count| {
	var $unit = 1.U32
	var $remaining = 6.U8 - count
	while $remaining > 0 {
		$unit = $unit * 10
		$remaining = $remaining - 1
	}
	$unit
}

effective_offset = |offset| match offset {
	UnassertedUtc => FixedOffset.from_seconds(0)
	Asserted(value) => value
}

digit = |byte| byte >= 48 and byte <= 57

# All calls use a positive power-of-ten divisor and at most its decimal width.
# The last division may yield zero only after emitting the final digit. Every
# emitted digit is in 0..9; the buffer is consumed without retaining an alias.
append_decimal : List(U8), U32, U32, U8 -> List(U8)
append_decimal = |initial, number, first_divisor, count| {
	var $bytes = initial
	var $divisor = first_divisor
	var $remaining = count
	while $remaining > 0 {
		digit_value = U32.rem_by(U32.div_trunc_by(number, $divisor), 10)
		$bytes = $bytes.append(digit_value.to_u8_wrap() + 48)
		$divisor = U32.div_trunc_by($divisor, 10)
		$remaining = $remaining - 1
	}
	$bytes
}

# RFC 3339 §5.8's independently stated equal-instant example.
# https://www.rfc-editor.org/rfc/rfc3339.html#section-5.8
expect {
	local = OffsetTimestamp.parse("1996-12-19T16:39:57-08:00")?
	utc = OffsetTimestamp.parse("1996-12-20T00:39:57Z")?
	OffsetTimestamp.boundary(local) == OffsetTimestamp.boundary(utc) and local != utc
}
# RFC 9557 §2 changes Z to the semantics of -00:00, but not +00:00.
# https://www.rfc-editor.org/rfc/rfc9557.html#section-2
expect {
	utc = OffsetTimestamp.parse("1970-01-01t00:00:00z")?
	unknown = OffsetTimestamp.parse("1970-01-01T00:00:00-00:00")?
	asserted = OffsetTimestamp.parse("1970-01-01T00:00:00+00:00")?
	utc == unknown and utc != asserted and
		OffsetTimestamp.to_text(utc) == "1970-01-01T00:00:00Z" and
			OffsetTimestamp.to_text(asserted) == "1970-01-01T00:00:00+00:00" and
				OffsetTimestamp.boundary(utc) == Ok(PosixBoundary.from_microseconds(0))
}
expect {
	a = OffsetTimestamp.parse("1969-12-31T23:59:59.999999Z")?
	b = OffsetTimestamp.parse("2000-02-29T12:00:00.12+23:59")?
	c = OffsetTimestamp.parse("2000-02-29T12:00:00.120+23:59")?
	OffsetTimestamp.boundary(a) == Ok(PosixBoundary.from_microseconds(-1)) and b != c and
		OffsetTimestamp.boundary(b) == OffsetTimestamp.boundary(c) and
			OffsetTimestamp.to_text(c) == "2000-02-29T12:00:00.120+23:59"
}
expect {
	var $valid = Bool.True
	for text in ["0000-01-01T00:00:00-23:59", "9999-12-31T23:59:59.999999+23:59", "1985-04-12T23:20:50.52Z"] {
		value = OffsetTimestamp.parse(text)?
		$valid = $valid and OffsetTimestamp.to_text(value) == text and OffsetTimestamp.parse(OffsetTimestamp.to_text(value)) == Ok(value)
	}
	$valid
}
expect {
	OffsetTimestamp.parse("2001-02-29T00:00:00Z") == Err(InvalidDate) and
		OffsetTimestamp.parse("2000-01-01T24:00:00Z") == Err(InvalidTime) and
			OffsetTimestamp.parse("1990-12-31T23:59:60Z") == Err(UnsupportedLeapSecond) and
				OffsetTimestamp.parse("2000-01-01T00:00:00.1234560Z") == Err(UnsupportedPrecision) and
					OffsetTimestamp.parse("2000-01-01T00:00:00Z[Europe/Paris]") == Err(UnsupportedAnnotations) and
						OffsetTimestamp.parse("2000-01-01T00:00:00+24:00") == Err(InvalidOffset) and
							OffsetTimestamp.parse("2000-01-01T00:00:00+00:60") == Err(InvalidOffset) and
								OffsetTimestamp.parse("2000-01-01T00:00:00+01:") == Err(Incomplete) and
									OffsetTimestamp.parse("2000-01-01T00:00:00+01:x") == Err(Malformed) and
										OffsetTimestamp.parse("2000-01-01T00:00:00.") == Err(Incomplete) and
											OffsetTimestamp.parse("2000-01-01T00:00:00.Z") == Err(Malformed)
}
expect {
	date = GregorianDate.from_fields({ year: 2000, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(1)?
	OffsetTimestamp.new({ date, clock, fraction_digits: 5, offset: UnassertedUtc }) == Err(UnsupportedPrecision) and
		OffsetTimestamp.new({ date, clock, fraction_digits: 7, offset: UnassertedUtc }) == Err(UnsupportedPrecision) and
			OffsetTimestamp.new({ date, clock, fraction_digits: 6, offset: Asserted(FixedOffset.from_seconds(I32.lowest)) }) == Err(InvalidOffset)
}

expect {
	value = OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(-1), UnassertedUtc, 6)?
	OffsetTimestamp.to_text(value) == "1969-12-31T23:59:59.999999Z" and
		OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(-1), UnassertedUtc, 5) == Err(UnsupportedPrecision) and
			OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(I64.highest), UnassertedUtc, 6) == Err(OutOfRange) and
				OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(I64.lowest), UnassertedUtc, 6) == Err(OutOfRange)
}
expect {
	OffsetTimestamp.parse(Str.join_with(List.repeat("x", 257), "")) == Err(TooLarge) and
		OffsetTimestamp.parse(Str.join_with(List.repeat("x", 256), "")) == Err(Malformed)
}

expect {
	OffsetTimestamp.parse("2000-01-01T00:00:00.1234567garbage") == Err(Malformed) and
		OffsetTimestamp.parse("2000-01-01T00:00:00.1234567+24:00") == Err(InvalidOffset) and
			OffsetTimestamp.parse("2000-01-01T00:00:00.1234567") == Err(Incomplete) and
				OffsetTimestamp.parse("2000-99-01T") == Err(InvalidDate) and
					OffsetTimestamp.parse("2001-02-29T") == Err(InvalidDate) and
						OffsetTimestamp.parse("2000-01-01T24:") == Err(InvalidTime) and
							OffsetTimestamp.parse("2000-01-01T23:60:") == Err(InvalidTime) and
								OffsetTimestamp.parse("2000-01-01T00:00:00+24:") == Err(InvalidOffset)
}

expect {
	shorter = OffsetTimestamp.parse("1970-01-01T00:00:00.12Z")?
	longer = OffsetTimestamp.parse("1970-01-01T00:00:00.120+00:00")?
	left = match OffsetTimestamp.fact_at(shorter, 0) {
		Item(fact) => Ok(SemanticFact.kind(fact))
		End => Err(MissingFact)
	}?
	right = match OffsetTimestamp.fact_at(longer, 0) {
		Item(fact) => Ok(SemanticFact.kind(fact))
		End => Err(MissingFact)
	}?
	facts_match = match (left, right) {
		(TimestampDescription(a), TimestampDescription(b)) => a.kind == OffsetTimestamp and b.kind == OffsetTimestamp and
			a.local == b.local and a.fraction_digits == 2 and b.fraction_digits == 3 and
				a.offset == UnassertedUtc and b.offset == Asserted(FixedOffset.from_seconds(0)) and
					!a.zone_present and a.annotation_count == 0
		_ => Bool.False
	}
	facts_match and OffsetTimestamp.fact_count(shorter) == 1 and OffsetTimestamp.fact_at(shorter, 1) == End and
		OffsetTimestamp.fact_at(longer, U64.highest) == End and OffsetTimestamp.to_inspect(longer).count_utf8_bytes() <= 256
}

# R01/R14: precedence is part of the public parser contract. A malformed
# available fixed byte wins over earlier range errors; later offset syntax
# cannot hide clock errors, and precision rejection follows trailing syntax.
expect {
	var $valid = Bool.True
	for case in [
		{ text: "2000-99-01T00:00:0xZ", error: Malformed },
		{ text: "2000-99-01T99:99:99Z", error: InvalidDate },
		{ text: "2000-01-01T00:00:60.Z", error: Malformed },
		{ text: "2000-01-01T00:00:60.1garbage", error: UnsupportedLeapSecond },
		{ text: "2000-01-01T00:00:00.1234567+24:x0", error: Malformed },
		{ text: "2000-01-01T00:00:00.1234567+24:00[", error: InvalidOffset },
		{ text: "2000-01-01T00:00:00.1234567+00:00[", error: UnsupportedAnnotations },
		{ text: "2000-01-01T00:00:00.1234567+00:00", error: UnsupportedPrecision },
		{ text: "2000-01-01T00:00:00.12", error: Incomplete },
		{ text: "2000-01-01T00:00:00Zé", error: Malformed },
	] {
		$valid = $valid and OffsetTimestamp.parse(case.text) == Err(case.error)
	}
	$valid
}
