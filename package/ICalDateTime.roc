import SemanticFact
import GregorianDate
import CalendarDate
import ClockTime
import LocalDateTime
import FixedOffset
import PosixBoundary

## RFC 5545 section 3.3.5 extracted DATE-TIME values, profile datetime-values-v1.
## Accept YYYYMMDDTHHMMSS with optional Z, years 0001–9999, whole seconds.
## ASCII t/z are accepted and canonical output uses uppercase. Numeric offsets,
## fractions, lists, whitespace and content lines are malformed. Leap seconds
## are explicitly unsupported on this POSIX profile, never normalized to 59.
##
## Local means the value has no Z. A surrounding property may supply TZID;
## this value parser does not invent, retain or validate a property parameter.
## Without TZID the RFC property is floating. source/local_label expose the
## validated fields for the shared recurrence and zone APIs with explicit context.
## Equality includes the UTC/local form; no cross-form total order is defined.
## These are timestamp labels, not second-wide calendar selections.
##
## Parsing and formatting have constant work and bounded output. A syntactically
## valid truncated prefix returns Incomplete; malformed prefixes return Malformed.
## Source spelling and full ICS documents are outside this value profile.
##
## ```roc
## import time.ICalDateTime
## import time.PosixBoundary
## expect {
##     value = ICalDateTime.parse("19691231T235959Z")?
##     ICalDateTime.utc_boundary(value) == Ok(PosixBoundary.from_microseconds(-1000000))
## }
## ```
ICalDateTime :: { date : GregorianDate, clock : ClockTime, form : Form }.{
	Form : [Local, Utc]
	Error : [Malformed, Incomplete, OutOfRange, InvalidDate, InvalidTime, UnsupportedLeapSecond]

	## Generic encodings carry canonical text, never the opaque backing record.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : ICalDateTime, rest : state }, [InvalidICalDateTime(Error), Encoding(err), ..]))
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
				Err(error) => Err(InvalidICalDateTime(error))
			}
		}
	}

	encoder_for : encoding -> (ICalDateTime, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(ICalDateTime, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid ICalDateTime literal: ${Str.inspect(error)}"))
	}

	profile : Str
	profile = "rfc5545-datetime-values-v1"

	parse : Str -> Try(ICalDateTime, Error)
	parse = |text| {
		length = text.count_utf8_bytes()
		if length > 16 {
			return Err(Malformed)
		}
		bytes = text.to_utf8()
		var $index = 0.U64
		for byte in bytes {
			valid = if $index == 8 {
				byte == 84 or byte == 116
			} else if $index == 15 {
				byte == 90 or byte == 122
			} else {
				byte >= 48 and byte <= 57
			}
			if !valid {
				return Err(Malformed)
			}
			$index = $index + 1
		}
		if length < 15 {
			return Err(Incomplete)
		}
		year = digits(bytes, 0, 4).to_i64()
		if year == 0 {
			return Err(OutOfRange)
		}
		# Fixed two-digit fields are 0..99, so narrowing is exact.
		month = digits(bytes, 4, 2).to_u8_wrap()
		day = digits(bytes, 6, 2).to_u8_wrap()
		date = match GregorianDate.from_fields({ year, month, day }) {
			Ok(value) => value
			Err(_) => return Err(InvalidDate)
		}
		clock = match ClockTime.from_fields({ hour: digits(bytes, 9, 2).to_u8_wrap(), minute: digits(bytes, 11, 2).to_u8_wrap(), second: digits(bytes, 13, 2).to_u8_wrap(), microsecond: 0 }) {
			Ok(value) => value
			Err(UnsupportedLeapSecond) => return Err(UnsupportedLeapSecond)
			Err(_) => return Err(InvalidTime)
		}
		form = if length == 16 {
			Utc
		} else {
			Local
		}
		Ok({ date, clock, form })
	}

	form : ICalDateTime -> Form
	form = |value| value.form
	source : ICalDateTime -> { date : GregorianDate, clock : ClockTime }
	source = |value| { date: value.date, clock: value.clock }

	## A field label only; callers must preserve form when interpreting it.
	local_label : ICalDateTime -> LocalDateTime
	local_label = |value| LocalDateTime.new(CalendarDate.from_gregorian(value.date), value.clock)

	## Only explicit Z permits context-free POSIX conversion. A local value
	## requires the caller's interpretation context, even if the fields are zero.
	utc_boundary : ICalDateTime -> Try(PosixBoundary, [NeedsContext, OutOfRange, ..])
	utc_boundary = |value| match value.form {
		Local => Err(NeedsContext)
		Utc => FixedOffset.resolve(FixedOffset.from_seconds(0), local_label(value))
	}

	to_text : ICalDateTime -> Str
	to_text = |value| {
		date = GregorianDate.to_fields(value.date)
		clock = ClockTime.to_fields(value.clock)
		suffix = match value.form {
			Local => ""
			Utc => "Z"
		}
		"${pad(date.year.to_str(), 4)}${pad(date.month.to_str(), 2)}${pad(date.day.to_str(), 2)}T${pad(clock.hour.to_str(), 2)}${pad(clock.minute.to_str(), 2)}${pad(clock.second.to_str(), 2)}${suffix}"
	}
	is_eq : ICalDateTime, ICalDateTime -> Bool
	is_eq = |a, b| a.date == b.date and a.clock == b.clock and a.form == b.form
	to_hash : ICalDateTime, Hasher -> Hasher
	to_hash = |value, hasher| {
		marker = match value.form {
			Local => 0.U8
			Utc => 1
		}
		marker.to_hash(value.clock.to_hash(value.date.to_hash(hasher)))
	}

	## Declaration facts retain local versus UTC form. A local value records
	## its need for explicit zone context without choosing one or resolving it.
	fact_count : ICalDateTime -> U64
	fact_count = |value| if value.form == Local {
		2
	} else {
		1
	}
	fact_at : ICalDateTime, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| {
		if index >= fact_count(value) {
			return End
		}
		if index == 0 {
			Item(SemanticFact.new(ICalDateTimeDescription({ role: Standalone, local: local_label(value), form: value.form })))
		} else {
			Item(SemanticFact.new(Requirement(ZoneContext)))
		}
	}
	to_inspect : ICalDateTime -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "RFC datetime has a first semantic fact"
	}
}

# parse has proved the full length, digit positions and maximum four digits.
digits : List(U8), U64, U64 -> U16
digits = |bytes, start, length| {
	var $number = 0.U16
	for byte in bytes.sublist({ start, len: length }) {
		$number = $number * 10 + (byte - 48).to_u16()
	}
	$number
}

# Constructor invariants bound every decimal field to its output width.
pad : Str, U64 -> Str
pad = |text, width| "${"0".repeat(width - text.count_utf8_bytes())}${text}"

expect ICalDateTime.utc_boundary(ICalDateTime.parse("19700101T000000Z")?) == Ok(PosixBoundary.from_microseconds(0))
expect ICalDateTime.utc_boundary(ICalDateTime.parse("19691231T235959Z")?) == Ok(PosixBoundary.from_microseconds(-1000000))
expect ICalDateTime.utc_boundary(ICalDateTime.parse("19700101T000000")?) == Err(NeedsContext)
expect ICalDateTime.parse("19700101T000000") != ICalDateTime.parse("19700101T000000Z")
expect ICalDateTime.to_text(ICalDateTime.parse("00010101t000000z")?) == "00010101T000000Z"
expect ICalDateTime.to_text(ICalDateTime.parse("99991231T235959")?) == "99991231T235959"
expect ICalDateTime.parse("00000101T000000Z") == Err(OutOfRange)
expect ICalDateTime.parse("19000229T000000Z") == Err(InvalidDate)
expect ICalDateTime.parse("20000229T240000Z") == Err(InvalidTime)
expect ICalDateTime.parse("19970630T235960Z") == Err(UnsupportedLeapSecond)
expect {
	var $valid = Bool.True
	for text in ["", "1970", "19700101", "19700101T", "19700101T00000"] {
		$valid = $valid and ICalDateTime.parse(text) == Err(Incomplete)
	}
	for text in ["X", "1970-", "19700101X000000", "19700101T000000+0000", "19700101T000000.0Z", "19700101T000000ZZ", "19700101T000000 "] {
		$valid = $valid and ICalDateTime.parse(text) == Err(Malformed)
	}
	$valid
}

expect {
	utc = ICalDateTime.parse("19970902T090000Z")?
	local = ICalDateTime.parse("19970902T090000")?
	ICalDateTime.fact_at(utc, 0) == Item(SemanticFact.new(ICalDateTimeDescription({ role: Standalone, local: ICalDateTime.local_label(utc), form: Utc }))) and
		ICalDateTime.fact_at(local, 0) == Item(SemanticFact.new(ICalDateTimeDescription({ role: Standalone, local: ICalDateTime.local_label(utc), form: Local }))) and
			ICalDateTime.fact_count(utc) == 1 and ICalDateTime.fact_count(local) == 2 and
				ICalDateTime.fact_at(local, 1) == Item(SemanticFact.new(Requirement(ZoneContext))) and
					ICalDateTime.fact_at(utc, 1) == End and ICalDateTime.fact_at(local, 2) == End and
						ICalDateTime.fact_at(local, U64.highest) == End and ICalDateTime.to_inspect(local).count_utf8_bytes() <= 256
}
