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
## Parsing checks a 256-byte limit before copying; construction, conversion and
## formatting have constant bounded work. Native persistence is a separate format.
OffsetTimestamp :: { date : GregorianDate, clock : ClockTime, fraction_digits : U8, offset : Offset }.{
	Offset : [UnassertedUtc, Asserted(FixedOffset)]
	Parts : { date : GregorianDate, clock : ClockTime, fraction_digits : U8, offset : Offset }
	Error : [Malformed, Incomplete, InvalidDate, InvalidTime, InvalidOffset, OutOfRange, TooLarge, UnsupportedPrecision, UnsupportedLeapSecond, UnsupportedAnnotations]
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
		bytes = text.to_utf8()
		length = bytes.len()
		# Validate every available fixed-field byte before classifying a prefix.
		var index = 0.U64
		while index < length and index < 19 {
			byte = at(bytes, index)
			valid = if index == 4 or index == 7 {
				byte == 45
			}
				else if index == 10 {
					byte == 84 or byte == 116
				}
					else if index == 13 or index == 16 {
						byte == 58
					}
						else {
							digit(byte)
						}
			if !valid {
				return Err(Malformed)
			}
			index = index + 1
		}
		if length >= 7 {
			month = digits(bytes, 5, 2)
			if month < 1 or month > 12 {
				return Err(InvalidDate)
			}
		}
		if length >= 13 and digits(bytes, 11, 2) > 23 {
			return Err(InvalidTime)
		}
		if length >= 16 and digits(bytes, 14, 2) > 59 {
			return Err(InvalidTime)
		}
		if length < 19 {
			if length >= 10 {
				match GregorianDate.from_fields({ year: digits(bytes, 0, 4).to_i64(), month: digits(bytes, 5, 2).to_u8_wrap(), day: digits(bytes, 8, 2).to_u8_wrap() }) {
					Ok(_) => {}
					Err(_) => return Err(InvalidDate)
				}
			}
			return Err(Incomplete)
		}
		date = match GregorianDate.from_fields({ year: digits(bytes, 0, 4).to_i64(), month: digits(bytes, 5, 2).to_u8_wrap(), day: digits(bytes, 8, 2).to_u8_wrap() }) {
			Ok(value) => value
			Err(_) => return Err(InvalidDate)
		}
		var fractional = 0.U32
		var count = 0.U8
		index = 19
		if index < length and at(bytes, index) == 46 {
			index = index + 1
			start = index
			while index < length and digit(at(bytes, index)) {
				if count < 6 {
					fractional = fractional * 10 + (at(bytes, index) - 48).to_u32()
				}
				if count < 7 {
					count = count + 1
				}
				index = index + 1
			}
			if index == start {
				if index == length {
					return Err(Incomplete)
				}
				return Err(Malformed)
			}
		}
		# Preserve only a safe placeholder while validating the remaining grammar.
		# Inputs over six digits cannot reach construction.
		clock_count = if count > 6 {
			6.U8
		} else {
			count
		}
		clock = match ClockTime.from_fields({ hour: digits(bytes, 11, 2).to_u8_wrap(), minute: digits(bytes, 14, 2).to_u8_wrap(), second: digits(bytes, 17, 2).to_u8_wrap(), microsecond: fractional * fraction_unit(clock_count) }) {
			Ok(value) => value
			Err(UnsupportedLeapSecond) => return Err(UnsupportedLeapSecond)
			Err(_) => return Err(InvalidTime)
		}
		if index == length {
			return Err(Incomplete)
		}
		var offset = UnassertedUtc
		marker = at(bytes, index)
		if marker == 90 or marker == 122 {
			index = index + 1
		} else if marker == 43 or marker == 45 {
			start = index
			index = index + 1
			while index < length and index < start + 6 {
				byte = at(bytes, index)
				valid = if index == start + 3 {
					byte == 58
				} else {
					digit(byte)
				}
				if !valid {
					return Err(Malformed)
				}
				index = index + 1
			}
			if index >= start + 3 and digits(bytes, start + 1, 2) > 23 {
				return Err(InvalidOffset)
			}
			if index < start + 6 {
				return Err(Incomplete)
			}
			hours = digits(bytes, start + 1, 2)
			minutes = digits(bytes, start + 4, 2)
			if hours > 23 or minutes > 59 {
				return Err(InvalidOffset)
			}
			seconds = (hours * 3600 + minutes * 60).to_i32_wrap()
			if marker == 43 or seconds != 0 {
				offset = Asserted(
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
		if index < length {
			if at(bytes, index) == 91 {
				return Err(UnsupportedAnnotations)
			}
			return Err(Malformed)
		}
		if count > 6 {
			return Err(UnsupportedPrecision)
		}
		new({ date, clock, fraction_digits: count, offset })
	}

	to_text : OffsetTimestamp -> Str
	to_text = |value| {
		date = GregorianDate.to_fields(value.date)
		clock = ClockTime.to_fields(value.clock)
		fraction = if value.fraction_digits == 0 {
			""
		} else {
			".${pad(U32.div_trunc_by(clock.microsecond, fraction_unit(value.fraction_digits)).to_str(), value.fraction_digits.to_u64())}"
		}
		offset = match value.offset {
			UnassertedUtc => "Z"
			Asserted(fixed) => {
				seconds = FixedOffset.to_seconds(fixed)
				sign = if seconds < 0 {
					"-"
				} else {
					"+"
				}
				absolute = if seconds < 0 {
					-seconds
				} else {
					seconds
				}
				"${sign}${pad(I32.div_trunc_by(absolute, 3600).to_str(), 2)}:${pad(I32.rem_by(I32.div_trunc_by(absolute, 60), 60).to_str(), 2)}"
			}
		}
		"${pad(date.year.to_str(), 4)}-${pad(date.month.to_str(), 2)}-${pad(date.day.to_str(), 2)}T${pad(clock.hour.to_str(), 2)}:${pad(clock.minute.to_str(), 2)}:${pad(clock.second.to_str(), 2)}${fraction}${offset}"
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
	to_inspect : OffsetTimestamp -> Str
	to_inspect = |value| "OffsetTimestamp(${to_text(value)})"
}

fraction_unit = |count| {
	var unit = 1.U32
	var remaining = 6.U8 - count
	while remaining > 0 {
		unit = unit * 10
		remaining = remaining - 1
	}
	unit
}

effective_offset = |offset| match offset {
	UnassertedUtc => FixedOffset.from_seconds(0)
	Asserted(value) => value
}

digit = |byte| byte >= 48 and byte <= 57

at = |bytes, index| match bytes.get(index) {
	Ok(byte) => byte
	Err(_) => crash "Offset timestamp byte index checked against input length"
}

digits = |bytes, start, count| {
	var value = 0.U32
	var index = start
	while index < start + count {
		value = value * 10 + (at(bytes, index) - 48).to_u32()
		index = index + 1
	}
	value
}

pad = |text, width| {
	var result = text
	while result.count_utf8_bytes() < width {
		result = "0${result}"
	}
	result
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
	var valid = Bool.True
	for text in ["0000-01-01T00:00:00-23:59", "9999-12-31T23:59:59.999999+23:59", "1985-04-12T23:20:50.52Z"] {
		value = OffsetTimestamp.parse(text)?
		valid = valid and OffsetTimestamp.to_text(value) == text and OffsetTimestamp.parse(OffsetTimestamp.to_text(value)) == Ok(value)
	}
	valid
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
