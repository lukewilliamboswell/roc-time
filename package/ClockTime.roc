## A local clock label at microsecond precision, without a date, zone or scale.
##
## Parse a time from an appointment form. Omitted seconds are zero; canonical
## output includes them. Typed quoted literals use the same validation.
##
## ```roc
## import time.ClockTime
##
## expect {
##     opening : ClockTime
##     opening = "09:30"
##     ClockTime.parse("09:30:00") == Ok(opening) and
##         ClockTime.to_text(opening) == "09:30:00"
## }
## ```
##
## Examples assume a package dependency named `time`.
ClockTime :: [Micros(I64)].{
	Fields : { hour : U8, minute : U8, second : U8, microsecond : U32 }
	Error : [Malformed, Incomplete, TooLarge, UnsupportedPrecision, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond]

	## Native boundary-label profile HH:MM[:SS[.fraction]], using ASCII digits
	## and one through six fractional digits when a decimal point is present.
	## Omitted seconds mean zero; supplied resolution and spelling are not retained.
	## No date, offset, zone, leap second, 24:00 or rounding is inferred.
	## Input is bounded to 64 UTF-8 bytes before decoding. Missing required tokens
	## return Incomplete; invalid grammar returns Malformed; fields use constructor
	## errors even when a later field is missing. Incomplete prefixes must admit a
	## valid completion; impossible first digits retain the corresponding field error.
	## More than six fractional digits always returns UnsupportedPrecision.
	## The seconds form follows the field grammar in RFC 3339 section 5.6
	## (https://www.rfc-editor.org/rfc/rfc3339#section-5.6, July 2002).
	## Optional seconds are a native extension, not RFC timestamp conformance.
	profile : Str
	profile = "clock-label-v1"

	parse : Str -> Try(ClockTime, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		empty_fields = { hour: 0.U8, minute: 0.U8, second: 0.U8, microsecond: 0.U32 }
		hour = pair(bytes, 0, empty_fields)?
		hour_fields = { ..empty_fields, hour }
		separator(bytes, 2, 58, hour_fields)?
		minute = pair(bytes, 3, hour_fields)?
		minute_fields = { ..hour_fields, minute }
		var $second = 0.U8
		var $microsecond = 0.U32
		if bytes.len() > 5 {
			separator(bytes, 5, 58, minute_fields)?
			$second = pair(bytes, 6, minute_fields)?
			if bytes.len() > 8 {
				separator(bytes, 8, 46, { ..minute_fields, second: $second })?
				if bytes.len() == 9 {
					_ = from_fields({ ..minute_fields, second: $second })?
					return Err(Incomplete)
				}
				var $position = 9.U64
				while $position < bytes.len() {
					byte = match bytes.get($position) {
						Ok(found) => found
						Err(_) => return Err(Incomplete)
					}
					if byte < 48 or byte > 57 {
						return Err(Malformed)
					}
					if $position >= 15 {
						return Err(UnsupportedPrecision)
					}
					$microsecond = $microsecond * 10 + (byte - 48).to_u32()
					$position = $position + 1
				}
				while $position < 15 {
					$microsecond = $microsecond * 10
					$position = $position + 1
				}
			}
		}
		from_fields({ hour, minute, second: $second, microsecond: $microsecond })
	}

	## Canonical output includes seconds and the shortest exact decimal fraction.
	to_text : ClockTime -> Str
	to_text = |value| {
		fields = to_fields(value)
		base = "${two_digits(fields.hour)}:${two_digits(fields.minute)}:${two_digits(fields.second)}"
		if fields.microsecond == 0 {
			return base
		}
		var $fraction = fields.microsecond
		var $width = 6.U64
		while U32.rem_by($fraction, 10) == 0 {
			$fraction = U32.div_trunc_by($fraction, 10)
			$width = $width - 1
		}
		var $digits = $fraction.to_str()
		while $digits.count_utf8_bytes() < $width {
			$digits = "0${$digits}"
		}
		"${base}.${$digits}"
	}

	parser_for : encoding -> (state -> Try({ value : ClockTime, rest : state }, [InvalidClockTime(Error), Encoding(err), ..]))
		where [encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err)]
	parser_for = |encoding| {
		Encoding : encoding
		|state| {
			parsed = match Encoding.parse_str(encoding, state) {
				Ok(value) => value
				Err(error) => return Err(Encoding(error))
			}
			match parse(parsed.value) {
				Ok(value) => Ok({ value, rest: parsed.rest })
				Err(error) => Err(InvalidClockTime(error))
			}
		}
	}

	encoder_for : encoding -> (ClockTime, state -> Try(state, err))
		where [encoding.encode_str : Str, state -> Try(state, err)]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed literals validate through parse; runtime interpolation requires parse.
	from_quote : Str -> Try(ClockTime, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid ClockTime literal: ${Str.inspect(error)}"))
	}

	from_fields : Fields -> Try(ClockTime, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	from_fields = |fields| {
		if fields.hour > 23 {
			return Err(InvalidHour)
		}
		if fields.minute > 59 {
			return Err(InvalidMinute)
		}
		if fields.second == 60 {
			return Err(UnsupportedLeapSecond)
		}
		if fields.second > 59 {
			return Err(InvalidSecond)
		}
		if fields.microsecond > 999999 {
			return Err(InvalidMicrosecond)
		}
		Ok(Micros(fields.hour.to_i64() * 3600000000 + fields.minute.to_i64() * 60000000 + fields.second.to_i64() * 1000000 + fields.microsecond.to_i64()))
	}

	from_microseconds_since_midnight : I64 -> Try(ClockTime, [OutOfRange, ..])
	from_microseconds_since_midnight = |number| {
		if number < 0 or number >= 86400000000 {
			Err(OutOfRange)
		} else {
			Ok(Micros(number))
		}
	}

	to_microseconds_since_midnight : ClockTime -> I64
	to_microseconds_since_midnight = |Micros(number)| number

	to_fields : ClockTime -> Fields
	to_fields = |Micros(number)| {
		# The opaque constructor bounds number to one nonnegative nominal day.
		{
			hour: I64.div_trunc_by(number, 3600000000).to_u8_wrap(),
			minute: I64.rem_by(I64.div_trunc_by(number, 60000000), 60).to_u8_wrap(),
			second: I64.rem_by(I64.div_trunc_by(number, 1000000), 60).to_u8_wrap(),
			microsecond: I64.rem_by(number, 1000000).to_u32_wrap(),
		}
	}

	is_eq : ClockTime, ClockTime -> Bool
	is_eq = |Micros(a), Micros(b)| a == b
	is_lt : ClockTime, ClockTime -> Bool
	is_lt = |Micros(a), Micros(b)| a < b
	is_lte : ClockTime, ClockTime -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b
	is_gt : ClockTime, ClockTime -> Bool
	is_gt = |Micros(a), Micros(b)| a > b
	is_gte : ClockTime, ClockTime -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b
	to_hash : ClockTime, Hasher -> Hasher
	to_hash = |Micros(number), hasher| number.to_hash(hasher)
	to_inspect : ClockTime -> Str
	to_inspect = |Micros(number)| "ClockTime(${number.to_str()} microseconds since local midnight)"

	expect from_fields({ hour: 24, minute: 0, second: 0, microsecond: 0 }) == Err(InvalidHour)
	expect from_fields({ hour: 0, minute: 60, second: 0, microsecond: 0 }) == Err(InvalidMinute)
	expect from_fields({ hour: 23, minute: 59, second: 60, microsecond: 0 }) == Err(UnsupportedLeapSecond)
	expect from_fields({ hour: 0, minute: 0, second: 61, microsecond: 0 }) == Err(InvalidSecond)
	expect from_fields({ hour: 0, minute: 0, second: 0, microsecond: 1000000 }) == Err(InvalidMicrosecond)
	expect from_microseconds_since_midnight(-1) == Err(OutOfRange)
	expect from_microseconds_since_midnight(86400000000) == Err(OutOfRange)

	# Field fixtures independently transcribe the partial-time field grammar
	# in RFC 3339 section 5.6; 23:20:50.52 is the clock-field projection of
	# section 5.8's first example (the date/offset are deliberately not retained).
	# The 09:30 fixture is the native omitted-seconds extension.
	expect {
		var $valid = Bool.True
		for fixture in [
			{ text: "23:20:50.52", fields: { hour: 23.U8, minute: 20.U8, second: 50.U8, microsecond: 520000.U32 }, canonical: "23:20:50.52" },
			{ text: "00:00:00", fields: { hour: 0.U8, minute: 0.U8, second: 0.U8, microsecond: 0.U32 }, canonical: "00:00:00" },
			{ text: "23:59:59.999999", fields: { hour: 23, minute: 59, second: 59, microsecond: 999999 }, canonical: "23:59:59.999999" },
			{ text: "09:30", fields: { hour: 9, minute: 30, second: 0, microsecond: 0 }, canonical: "09:30:00" },
			{ text: "12:34:56.001200", fields: { hour: 12, minute: 34, second: 56, microsecond: 1200 }, canonical: "12:34:56.0012" },
			{ text: "01:02:03.000001", fields: { hour: 1, minute: 2, second: 3, microsecond: 1 }, canonical: "01:02:03.000001" },
			{ text: "01:02:03.000000", fields: { hour: 1, minute: 2, second: 3, microsecond: 0 }, canonical: "01:02:03" },
		] {
			value = parse(fixture.text)?
			$valid = $valid and to_fields(value) == fixture.fields and to_text(value) == fixture.canonical
		}
		$valid
	}
	expect parse("24:00") == Err(InvalidHour)
	expect parse("25:") == Err(InvalidHour)
	expect parse("09:99:") == Err(InvalidMinute)
	expect parse("09:30:60.") == Err(UnsupportedLeapSecond)
	expect parse("9") == Err(InvalidHour)
	expect parse("09:7") == Err(InvalidMinute)
	expect parse("09:30:6") == Err(InvalidSecond)
	expect parse("25:7") == Err(InvalidHour)
	expect parse("09:99:6") == Err(InvalidMinute)
	expect parse("00:60") == Err(InvalidMinute)
	expect parse("23:59:60") == Err(UnsupportedLeapSecond)
	expect parse("00:00:61") == Err(InvalidSecond)
	expect parse("00:00:00.0000000") == Err(UnsupportedPrecision)
	expect ["", "0", "00", "00:", "00:0", "00:00:", "00:00:0", "00:00:00."].all(|text| parse(text) == Err(Incomplete))
	expect ["9:30", "09-30", "09:30Z", "09:30.1", "09:30:00+00:00", "09:30:00,1", "０9:30", "09:30:00.1x"].all(|text| parse(text) == Err(Malformed))
	expect parse("00000000000000000000000000000000000000000000000000000000000000000") == Err(TooLarge)

	# Independent bounded odometer model: enumerate all seconds by carrying
	# fields, rather than using the production multiplication/division formulas.
	# Fractional endpoints exercise both sides of every second boundary.
	expect {
		var $number = 0.I64
		var $hour = 0.U8
		var $valid = Bool.True
		while $hour < 24 {
			var $minute = 0.U8
			while $minute < 60 {
				var $second = 0.U8
				while $second < 60 {
					for microsecond in [0.U32, 1, 999999] {
						fields = { hour: $hour, minute: $minute, second: $second, microsecond }
						value = from_fields(fields)?
						$valid = $valid and to_fields(value) == fields and
							from_microseconds_since_midnight($number + microsecond.to_i64()) == Ok(value)
					}
					$number = $number + 1000000
					$second = $second + 1
				}
				$minute = $minute + 1
			}
			$hour = $hour + 1
		}
		$valid and $number == 86400000000
	}
}

# Private syntax helpers validate completed prefixes through the public
# constructor only on incomplete paths. Successful parses construct once.
pair = |bytes, position, completed_fields| {
	var $value = 0.U8
	for index in [position, position + 1] {
		byte = match bytes.get(index) {
			Ok(value) => value
			Err(_) => {
				_ = ClockTime.from_fields(completed_fields)?
				# Completed higher fields take priority; only a missing second
				# digit can expose an impossible first-digit prefix here.
				if index > position {
					if position == 0 and $value > 2 {
						return Err(InvalidHour)
					}
					if position == 3 and $value > 5 {
						return Err(InvalidMinute)
					}
					if position == 6 and $value > 5 {
						return Err(InvalidSecond)
					}
				}
				return Err(Incomplete)
			}
		}
		if byte < 48 or byte > 57 {
			return Err(Malformed)
		}
		$value = $value * 10 + byte - 48
	}
	Ok($value)
}

separator = |bytes, position, expected, completed_fields| match bytes.get(position) {
	Ok(byte) => if byte == expected {
		Ok({})
	} else {
		Err(Malformed)
	}
	Err(_) => {
		_ = ClockTime.from_fields(completed_fields)?
		Err(Incomplete)
	}
}

two_digits = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
