import ClockLabel

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

	## Clock fields: hour 0..23, minute and second 0..59, microsecond 0..999999.
	## Pass the complete record to from_fields for validation.
	Fields : { hour : U8, minute : U8, second : U8, microsecond : U32 }

	## Clock parsing failures distinguish incomplete or malformed text, profile
	## limits, invalid fields and unsupported leap seconds or fractional precision.
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

	## Parse HH:MM, HH:MM:SS or HH:MM:SS.fraction with one to six fractional digits.
	## Omitted seconds are zero. Reject leap seconds, 24:00, finer precision and
	## text outside the declared profile with structured errors.
	parse : Str -> Try(ClockTime, Error)
	parse = |text| {
		fields = ClockLabel.parse(text, 6)?
		Ok(from_validated_fields({ hour: fields.hour, minute: fields.minute, second: fields.second, microsecond: fields.fraction }))
	}

	## Canonical output includes seconds and the shortest exact decimal fraction.
	to_text : ClockTime -> Str
	to_text = |value| {
		fields = value.to_fields()
		ClockLabel.to_text({ hour: fields.hour, minute: fields.minute, second: fields.second, fraction: fields.microsecond }, 6)
	}

	## Build a decoder for one encoded clock-label string. Return the clock and
	## unconsumed state. Validation failures use the format-owned invalid_value error;
	## parse retains detailed clock errors.
	parser_for : encoding -> (state -> Try({ value : ClockTime, rest : state }, err))
		where [encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err), encoding.invalid_value : encoding, state -> err]
	parser_for = |encoding| {
		Encoding : encoding
		|state| {
			parsed = match Encoding.parse_str(encoding, state) {
				Ok(value) => value
				Err(error) => return Err(error)
			}
			match parse(parsed.value) {
				Ok(value) => Ok({ value, rest: parsed.rest })
				Err(_) => Err(Encoding.invalid_value(encoding, state))
			}
		}
	}

	## Build an encoder that writes the canonical clock string, including seconds,
	## through the supplied string encoding.
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

	## Validate a local clock label: hours 0..23, minutes/seconds 0..59 and
	## microseconds 0..999999. A second of 60 returns UnsupportedLeapSecond.
	## No date or timezone is attached.
	from_fields : Fields -> Try(ClockTime, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond])
	from_fields = |fields| {
		ClockLabel.validate({ hour: fields.hour, minute: fields.minute, second: fields.second, fraction: fields.microsecond })?
		if fields.microsecond > 999999 {
			return Err(InvalidMicrosecond)
		}
		Ok(from_validated_fields(fields))
	}

	## Construct a clock label from 0 through 86399999999 microseconds since
	## nominal midnight. Other values return OutOfRange; the input does not wrap.
	from_microseconds_since_midnight : I64 -> Try(ClockTime, [OutOfRange])
	from_microseconds_since_midnight = |number| {
		if number < 0 or number >= 86400000000 {
			Err(OutOfRange)
		} else {
			Ok(Micros(number))
		}
	}

	## Read microseconds since nominal midnight, in 0..86399999999.
	## This clock coordinate does not account for timezone transitions.
	to_microseconds_since_midnight : ClockTime -> I64
	to_microseconds_since_midnight = |Micros(number)| number

	## Read the validated hour, minute, second and microsecond fields.
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

	## Equality of clock labels within the same nominal day; values of other temporal domains must be converted explicitly.
	is_eq : _

	## Order by the native scalar coordinate.
	order_relative_to : ClockTime, ClockTime -> [Before, Same, After]
	order_relative_to = |left, right| left.to_microseconds_since_midnight().order_relative_to(right.to_microseconds_since_midnight())

	## Whether the first of two clock labels within the same nominal day precedes the second in their numeric order.
	is_lt : ClockTime, ClockTime -> Bool
	is_lt = |Micros(a), Micros(b)| a < b

	## Whether the first of two clock labels within the same nominal day precedes or equals the second.
	is_lte : ClockTime, ClockTime -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b

	## Whether the first of two clock labels within the same nominal day follows the second in their numeric order.
	is_gt : ClockTime, ClockTime -> Bool
	is_gt = |Micros(a), Micros(b)| a > b

	## Whether the first of two clock labels within the same nominal day follows or equals the second.
	is_gte : ClockTime, ClockTime -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b

	## Hash clock labels within the same nominal day consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : _

	## Return a concise diagnostic description of these clock labels within the same nominal day.
	## Use explicit conversions or text serialization when storing or exchanging data.
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

from_validated_fields : ClockTime.Fields -> ClockTime
from_validated_fields = |fields| ClockTime.Micros(fields.hour.to_i64() * 3600000000 + fields.minute.to_i64() * 60000000 + fields.second.to_i64() * 1000000 + fields.microsecond.to_i64())
