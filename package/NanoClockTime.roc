import ClockTime
import PosixBoundary

## A local clock label at nanosecond precision, without a date, zone or scale.
##
## Use it for a time of day that a data source stores as nanoseconds since
## midnight, such as an Apache Arrow Time64(ns) value. The value keeps every
## nanosecond; conversion to the microsecond ClockTime takes an explicit
## rounding policy.
##
## ```roc
## import time.NanoClockTime
##
## expect {
##     # 12:00:00.000000001 as a Time64(ns) value
##     received = NanoClockTime.from_nanoseconds_since_midnight(43200000000001)
##     received.map_ok(NanoClockTime.to_text) == Ok("12:00:00.000000001") and
##         received.map_ok(|clock| NanoClockTime.to_clock(clock, RejectSubmicrosecond)) == Ok(Err(Submicrosecond))
## }
## ```
##
## Text and typed quoted literals use the same validation as ClockTime, with
## up to nine fractional digits.
##
## ```roc
## import time.NanoClockTime
##
## expect {
##     opening : NanoClockTime
##     opening = "09:30"
##     NanoClockTime.parse("09:30:00.000000000") == Ok(opening) and
##         NanoClockTime.to_text(opening) == "09:30:00"
## }
## ```
##
## Examples assume a package dependency named `time`.
NanoClockTime :: [Nanos(I64)].{

	## Clock fields: hour 0..23, minute and second 0..59, nanosecond 0..999999999.
	## Pass the complete record to from_fields for validation.
	Fields : { hour : U8, minute : U8, second : U8, nanosecond : U32 }

	## Clock parsing failures distinguish incomplete or malformed text, profile
	## limits, invalid fields and unsupported leap seconds or fractional precision.
	Error : [Malformed, Incomplete, TooLarge, UnsupportedPrecision, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidNanosecond]

	## Native boundary-label profile HH:MM[:SS[.fraction]], using ASCII digits
	## and one through nine fractional digits when a decimal point is present.
	## Omitted seconds mean zero; supplied resolution and spelling are not retained.
	## No date, offset, zone, leap second, 24:00 or rounding is inferred.
	## Input is bounded to 64 UTF-8 bytes before decoding. Missing required tokens
	## return Incomplete; invalid grammar returns Malformed; fields use constructor
	## errors even when a later field is missing. Incomplete prefixes must admit a
	## valid completion; impossible first digits retain the corresponding field error.
	## More than nine fractional digits always returns UnsupportedPrecision.
	## The seconds form follows the field grammar in RFC 3339 section 5.6
	## (https://www.rfc-editor.org/rfc/rfc3339#section-5.6, July 2002).
	## Optional seconds are a native extension, not RFC timestamp conformance.
	profile : Str
	profile = "clock-label-nanoseconds-v1"

	## Parse HH:MM, HH:MM:SS or HH:MM:SS.fraction with one to nine fractional digits.
	## Omitted seconds are zero. Reject leap seconds, 24:00, finer precision and
	## text outside the declared profile with structured errors.
	parse : Str -> Try(NanoClockTime, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		empty_fields = { hour: 0.U8, minute: 0.U8, second: 0.U8, nanosecond: 0.U32 }
		hour = pair(bytes, 0, empty_fields)?
		hour_fields = { ..empty_fields, hour }
		separator(bytes, 2, 58, hour_fields)?
		minute = pair(bytes, 3, hour_fields)?
		minute_fields = { ..hour_fields, minute }
		var $second = 0.U8
		var $nanosecond = 0.U32
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
					if $position >= 18 {
						return Err(UnsupportedPrecision)
					}
					$nanosecond = $nanosecond * 10 + (byte - 48).to_u32()
					$position = $position + 1
				}
				while $position < 18 {
					$nanosecond = $nanosecond * 10
					$position = $position + 1
				}
			}
		}
		from_fields({ hour, minute, second: $second, nanosecond: $nanosecond })
	}

	## Canonical output includes seconds and the shortest exact decimal fraction.
	to_text : NanoClockTime -> Str
	to_text = |value| {
		fields = to_fields(value)
		base = "${two_digits(fields.hour)}:${two_digits(fields.minute)}:${two_digits(fields.second)}"
		if fields.nanosecond == 0 {
			return base
		}
		var $fraction = fields.nanosecond
		var $width = 9.U64
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

	## Build a decoder for one encoded clock-label string. Return the clock and
	## unconsumed state. Validation failures use the format-owned invalid_value error;
	## parse retains detailed clock errors.
	parser_for : encoding -> (state -> Try({ value : NanoClockTime, rest : state }, err))
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
	encoder_for : encoding -> (NanoClockTime, state -> Try(state, err))
		where [encoding.encode_str : Str, state -> Try(state, err)]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed literals validate through parse; runtime interpolation requires parse.
	from_quote : Str -> Try(NanoClockTime, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid NanoClockTime literal: ${Str.inspect(error)}"))
	}

	## Validate a local clock label: hours 0..23, minutes/seconds 0..59 and
	## nanoseconds 0..999999999. A second of 60 returns UnsupportedLeapSecond.
	## No date or timezone is attached.
	from_fields : Fields -> Try(NanoClockTime, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidNanosecond])
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
		if fields.nanosecond > 999999999 {
			return Err(InvalidNanosecond)
		}
		Ok(Nanos(fields.hour.to_i64() * 3600000000000 + fields.minute.to_i64() * 60000000000 + fields.second.to_i64() * 1000000000 + fields.nanosecond.to_i64()))
	}

	## Construct a clock label from 0 through 86399999999999 nanoseconds since
	## nominal midnight. Other values return OutOfRange; the input does not wrap.
	from_nanoseconds_since_midnight : I64 -> Try(NanoClockTime, [OutOfRange])
	from_nanoseconds_since_midnight = |number| {
		if number < 0 or number >= 86400000000000 {
			Err(OutOfRange)
		} else {
			Ok(Nanos(number))
		}
	}

	## Read nanoseconds since nominal midnight, in 0..86399999999999.
	## This clock coordinate does not account for timezone transitions.
	to_nanoseconds_since_midnight : NanoClockTime -> I64
	to_nanoseconds_since_midnight = |Nanos(number)| number

	## Read the validated hour, minute, second and nanosecond fields.
	to_fields : NanoClockTime -> Fields
	to_fields = |Nanos(number)| {
		# The opaque constructor bounds number to one nonnegative nominal day.
		{
			hour: I64.div_trunc_by(number, 3600000000000).to_u8_wrap(),
			minute: I64.rem_by(I64.div_trunc_by(number, 60000000000), 60).to_u8_wrap(),
			second: I64.rem_by(I64.div_trunc_by(number, 1000000000), 60).to_u8_wrap(),
			nanosecond: I64.rem_by(number, 1000000000).to_u32_wrap(),
		}
	}

	## Equality of clock labels within the same nominal day; values of other temporal domains must be converted explicitly.
	is_eq : NanoClockTime, NanoClockTime -> Bool
	is_eq = |Nanos(a), Nanos(b)| a == b

	## Whether the first of two clock labels within the same nominal day precedes the second in their numeric order.
	is_lt : NanoClockTime, NanoClockTime -> Bool
	is_lt = |Nanos(a), Nanos(b)| a < b

	## Whether the first of two clock labels within the same nominal day precedes or equals the second.
	is_lte : NanoClockTime, NanoClockTime -> Bool
	is_lte = |Nanos(a), Nanos(b)| a <= b

	## Whether the first of two clock labels within the same nominal day follows the second in their numeric order.
	is_gt : NanoClockTime, NanoClockTime -> Bool
	is_gt = |Nanos(a), Nanos(b)| a > b

	## Whether the first of two clock labels within the same nominal day follows or equals the second.
	is_gte : NanoClockTime, NanoClockTime -> Bool
	is_gte = |Nanos(a), Nanos(b)| a >= b

	## Hash clock labels within the same nominal day consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : NanoClockTime, Hasher -> Hasher
	to_hash = |Nanos(number), hasher| number.to_hash(hasher)

	## Return a concise diagnostic description of these clock labels within the same nominal day.
	## Use explicit conversions or text serialization when storing or exchanging data.
	to_inspect : NanoClockTime -> Str
	to_inspect = |Nanos(number)| "NanoClockTime(${number.to_str()} nanoseconds since local midnight)"

	## Widen a microsecond clock label. The result is exact and always in range.
	from_clock : ClockTime -> NanoClockTime
	from_clock = |clock| Nanos(ClockTime.to_microseconds_since_midnight(clock) * 1000)

	## Narrow to a microsecond clock label under an explicit rounding policy.
	## RejectSubmicrosecond returns Submicrosecond for an inexact value. A value
	## that rounds up to the next midnight returns OutOfRange; the day does not carry.
	to_clock : NanoClockTime, PosixBoundary.Rounding -> Try(ClockTime, [Submicrosecond, OutOfRange])
	to_clock = |Nanos(number), policy| {
		# The rounding is the same integer quantization PosixBoundary uses for nanoseconds.
		micros = PosixBoundary.to_microseconds(PosixBoundary.from_nanoseconds_with_rounding(number.to_i128(), policy)?)
		ClockTime.from_microseconds_since_midnight(micros)
	}

	## Split into the microsecond clock label at or before this value and the
	## remaining nanoseconds, 0..999. Recombining the two parts is exact.
	split_microseconds : NanoClockTime -> { clock : ClockTime, nanosecond : U16 }
	split_microseconds = |Nanos(number)| {
		# The opaque constructor keeps number nonnegative, so truncation is floor.
		clock = match ClockTime.from_microseconds_since_midnight(I64.div_trunc_by(number, 1000)) {
			Ok(value) => value
			Err(OutOfRange) => crash "NanoClockTime bounds one nominal day"
		}
		{ clock, nanosecond: I64.rem_by(number, 1000).to_u16_wrap() }
	}

	expect parse("23:59:59.123456789").map_ok(to_text) == Ok("23:59:59.123456789")
	expect parse("23:59:59.100000000").map_ok(to_text) == Ok("23:59:59.1")
	expect parse("12:00:00.1234567891") == Err(UnsupportedPrecision)
	expect to_inspect(Nanos(1)) == "NanoClockTime(1 nanoseconds since local midnight)"

	# Widening multiplies by 1000 at both ends of the clock domain; narrowing
	# the widened value back is exact under the reject policy.
	expect {
		var $valid = Bool.True
		for micros in [0.I64, 1, 999999, 86399999999] {
			clock = ClockTime.from_microseconds_since_midnight(micros)?
			wide = from_clock(clock)
			$valid = $valid and to_nanoseconds_since_midnight(wide) == micros * 1000 and
				to_clock(wide, RejectSubmicrosecond) == Ok(clock)
		}
		$valid
	}

	# Expected microseconds are written out by hand from the policy definitions,
	# not computed: below, at and above each half, on odd and even quotients.
	expect {
		var $valid = Bool.True
		for row in [
			{ nanos: 1000.I64, floor: 1.I64, ceiling: 1.I64, nearest: 1.I64 },
			{ nanos: 1, floor: 0, ceiling: 1, nearest: 0 },
			{ nanos: 1499, floor: 1, ceiling: 2, nearest: 1 },
			{ nanos: 1500, floor: 1, ceiling: 2, nearest: 2 },
			{ nanos: 1501, floor: 1, ceiling: 2, nearest: 2 },
			{ nanos: 2500, floor: 2, ceiling: 3, nearest: 2 },
			{ nanos: 2501, floor: 2, ceiling: 3, nearest: 3 },
			{ nanos: 86399999998999, floor: 86399999998, ceiling: 86399999999, nearest: 86399999999 },
		] {
			value = from_nanoseconds_since_midnight(row.nanos)?
			expect_micros = |micros| ClockTime.from_microseconds_since_midnight(micros)
			exact = if I64.rem_by(row.nanos, 1000) == 0 {
				expect_micros(row.floor)
			} else {
				Err(Submicrosecond)
			}
			$valid = $valid and
				to_clock(value, Floor) == expect_micros(row.floor) and
					to_clock(value, TowardZero) == expect_micros(row.floor) and
						to_clock(value, Ceiling) == expect_micros(row.ceiling) and
							to_clock(value, NearestTiesEven) == expect_micros(row.nearest) and
								to_clock(value, RejectSubmicrosecond) == exact
		}
		$valid
	}

	# Rounding up to 24:00 fails; the last values that round down still succeed.
	expect from_nanoseconds_since_midnight(86399999999001).map_ok(|v| to_clock(v, Ceiling)) == Ok(Err(OutOfRange))
	expect from_nanoseconds_since_midnight(86399999999500).map_ok(|v| to_clock(v, NearestTiesEven)) == Ok(Err(OutOfRange))
	expect from_nanoseconds_since_midnight(86399999999499).map_ok(|v| to_clock(v, NearestTiesEven)) == Ok(ClockTime.from_microseconds_since_midnight(86399999999))
	expect from_nanoseconds_since_midnight(86399999999999).map_ok(|v| to_clock(v, Floor)) == Ok(ClockTime.from_microseconds_since_midnight(86399999999))

	# The split floors to the microsecond and the remainder recombines exactly.
	expect {
		var $valid = Bool.True
		for nanos in [0.I64, 1, 999, 1000, 1001, 43200000000001, 86399999999999] {
			value = from_nanoseconds_since_midnight(nanos)?
			parts = split_microseconds(value)
			micros = ClockTime.to_microseconds_since_midnight(parts.clock)
			$valid = $valid and parts.nanosecond < 1000 and micros * 1000 + parts.nanosecond.to_i64() == nanos and
				to_clock(value, Floor) == Ok(parts.clock)
		}
		$valid
	}

	# Order and hashing follow the nanosecond count; one nanosecond is distinct.
	expect {
		a = from_nanoseconds_since_midnight(43200000000000)?
		b = from_nanoseconds_since_midnight(43200000000001)?
		same_a = from_clock(ClockTime.from_microseconds_since_midnight(43200000000)?)
		keys = Dict.empty().insert(a, "a").insert(b, "b")
		a < b and a <= b and b > a and b >= a and a != b and a == same_a and
			!(a < same_a) and !(a > same_a) and a <= same_a and a >= same_a and !(b <= a) and !(a >= b) and
				keys.get(same_a) == Ok("a") and keys.len() == 2
	}

	expect from_fields({ hour: 24, minute: 0, second: 0, nanosecond: 0 }) == Err(InvalidHour)
	expect from_fields({ hour: 0, minute: 60, second: 0, nanosecond: 0 }) == Err(InvalidMinute)
	expect from_fields({ hour: 23, minute: 59, second: 60, nanosecond: 0 }) == Err(UnsupportedLeapSecond)
	expect from_fields({ hour: 0, minute: 0, second: 61, nanosecond: 0 }) == Err(InvalidSecond)
	expect from_fields({ hour: 0, minute: 0, second: 0, nanosecond: 1000000000 }) == Err(InvalidNanosecond)
	expect from_nanoseconds_since_midnight(-1) == Err(OutOfRange)
	expect from_nanoseconds_since_midnight(86400000000000) == Err(OutOfRange)

	# Field fixtures independently transcribe the partial-time field grammar
	# in RFC 3339 section 5.6; 23:20:50.52 is the clock-field projection of
	# section 5.8's first example (the date/offset are deliberately not retained).
	# The 09:30 fixture is the native omitted-seconds extension.
	expect {
		var $valid = Bool.True
		for fixture in [
			{ text: "23:20:50.52", fields: { hour: 23.U8, minute: 20.U8, second: 50.U8, nanosecond: 520000000.U32 }, canonical: "23:20:50.52" },
			{ text: "00:00:00", fields: { hour: 0.U8, minute: 0.U8, second: 0.U8, nanosecond: 0.U32 }, canonical: "00:00:00" },
			{ text: "23:59:59.999999999", fields: { hour: 23, minute: 59, second: 59, nanosecond: 999999999 }, canonical: "23:59:59.999999999" },
			{ text: "09:30", fields: { hour: 9, minute: 30, second: 0, nanosecond: 0 }, canonical: "09:30:00" },
			{ text: "12:34:56.001200", fields: { hour: 12, minute: 34, second: 56, nanosecond: 1200000 }, canonical: "12:34:56.0012" },
			{ text: "01:02:03.000000001", fields: { hour: 1, minute: 2, second: 3, nanosecond: 1 }, canonical: "01:02:03.000000001" },
			{ text: "01:02:03.000000", fields: { hour: 1, minute: 2, second: 3, nanosecond: 0 }, canonical: "01:02:03" },
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
	expect parse("00:00:00.0000000000") == Err(UnsupportedPrecision)
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
					for nanosecond in [0.U32, 1, 999999999] {
						fields = { hour: $hour, minute: $minute, second: $second, nanosecond }
						value = from_fields(fields)?
						$valid = $valid and to_fields(value) == fields and
							from_nanoseconds_since_midnight($number + nanosecond.to_i64()) == Ok(value)
					}
					$number = $number + 1000000000
					$second = $second + 1
				}
				$minute = $minute + 1
			}
			$hour = $hour + 1
		}
		$valid and $number == 86400000000000
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
				_ = NanoClockTime.from_fields(completed_fields)?
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
		_ = NanoClockTime.from_fields(completed_fields)?
		Err(Incomplete)
	}
}

two_digits = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
