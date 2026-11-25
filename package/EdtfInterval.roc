import Calendar
import CalendarInterval
import QualifiedCalendarValue
import EdtfDate
import SemanticFact

## EDTF date intervals with independently described endpoints. Known dates use
## EdtfDate's Gregorian 0000..9999 year/month/day profile and scoped qualifiers.
## An empty side means Unknown; '..' means explicitly Open. Both sides may be
## unknown or open, including '/' and '../..'. These are useful descriptions,
## not materialized coverage. Equal or overlapping date domains remain valid.
##
## The LOC examples 1964/2008 and 2004-02-01/2005-02 describe when endpoints
## occurred within the supplied calendar units. They do not assert exact year
## starts or half-open timestamp appointments. No source spelling, numerical
## tolerance, timezone or general uncertainty solver is implied.
## This is a declared subset, not full EDTF Level 0, 1 or 2 conformance.
## Parsing visits at most 129 UTF-8 bytes; each known side retains EdtfDate's
## 64-byte limit. Partial known dates retain side-specific Incomplete errors.
EdtfInterval :: { raw : CalendarInterval }.{

	## Interval syntax and provable order errors, or an identified endpoint's
	## existing date-profile validation failure.
	Error : [Malformed, Incomplete, TooLarge, ReversedBounds, Start(EdtfDate.Error), End(EdtfDate.Error)]

	## Decode one encoded string using this type's validated text parser.
	## Failures use the format's error type; parse retains detailed temporal errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : EdtfInterval, rest : state }, err))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
			encoding.invalid_value : encoding, state -> err,
		]
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

	## Encodes the canonical standard text as a string in the selected encoding; encoding failures pass through.
	encoder_for : encoding -> (EdtfInterval, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(EdtfInterval, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid EdtfInterval literal: ${Str.inspect(error)}"))
	}

	## The exact date-only interval profile supported by this adapter.
	profile : Str
	profile = "edtf-gregorian-date-interval-v1"

	## Construct through the shared native validator and date adapter. Known
	## descriptions keep their independent resolutions and qualifications.
	new : { start : CalendarInterval.Endpoint, end : CalendarInterval.Endpoint } -> Try(EdtfInterval, Error)
	new = |{ start, end }| {
		match check_endpoint(start) {
			Ok(_) => {}
			Err(error) => return Err(Start(error))
		}
		match check_endpoint(end) {
			Ok(_) => {}
			Err(error) => return Err(End(error))
		}
		raw = match CalendarInterval.new({ start, end }) {
			Ok(value) => value
			Err(ReversedBounds) => return Err(ReversedBounds)
			Err(Start(_)) => return Err(Start(UnsupportedResolution))
			Err(End(_)) => return Err(End(UnsupportedResolution))
		}
		Ok({ raw: raw })
	}

	## Check whether a native interval can be saved without losing meaning.
	from_description : CalendarInterval -> Try(EdtfInterval, Error)
	from_description = |raw| {
		parts = CalendarInterval.endpoints(raw)
		new({ start: parts.start, end: parts.end })
	}

	## Return the shared validated description. No calendar interpretation occurs.
	description : EdtfInterval -> CalendarInterval
	description = |value| value.raw

	## Parse one slash with known, unknown or explicitly open sides.
	parse : Str -> Try(EdtfInterval, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 129 {
			return Err(TooLarge)
		}
		parts = text.split_on("/")
		if parts.len() > 2 {
			return Err(Malformed)
		}
		start = match parse_endpoint(parts.first() ?? "") {
			Ok(value) => value
			Err(Incomplete) if parts.len() == 2 => return Err(Start(Malformed))
			Err(error) => return Err(Start(error))
		}
		if parts.len() != 2 {
			return Err(Incomplete)
		}
		end = match parse_endpoint(parts.get(1) ?? "") {
			Ok(value) => value
			Err(error) => return Err(End(error))
		}
		new({ start, end })
	}

	## Canonical EDTF text preserves knowledge, resolution and qualifier scopes.
	to_text : EdtfInterval -> Str
	to_text = |value| {
		parts = CalendarInterval.endpoints(value.raw)
		"${endpoint_text(parts.start)}/${endpoint_text(parts.end)}"
	}

	## Description equality; not extent equality between exact appointments.
	is_eq : EdtfInterval, EdtfInterval -> Bool
	is_eq = |a, b| a.raw == b.raw

	## Hash the declaration consistently with description equality.
	to_hash : EdtfInterval, Hasher -> Hasher
	to_hash = |value, hasher| value.raw.to_hash(hasher)

	## Number of bounded native facts, without interpretation.
	fact_count : EdtfInterval -> U64
	fact_count = |value| CalendarInterval.fact_count(value.raw)

	## Read the same endpoint knowledge and date facts as the native description.
	fact_at : EdtfInterval, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| CalendarInterval.fact_at(value.raw, index)

	## Concise diagnostic summary. Use to_text for persistence.
	to_inspect : EdtfInterval -> Str
	to_inspect = |value| "EdtfInterval(${to_text(value)}, unresolved)"
}

check_endpoint = |endpoint| match endpoint {
	Known(value) => match EdtfDate.from_description(value) {
		Ok(_) => Ok({})
		Err(error) => Err(error)
	}
	_ => Ok({})
}

parse_endpoint : Str -> Try(CalendarInterval.Endpoint, EdtfDate.Error)
parse_endpoint = |text| {
	if text == "" {
		return Ok(Unknown)
	}
	if text == "." {
		return Err(Incomplete)
	}
	if text == ".." {
		return Ok(Open)
	}
	match EdtfDate.parse(text) {
		Ok(value) => Ok(Known(EdtfDate.description(value)))
		Err(error) => Err(error)
	}
}

endpoint_text = |endpoint| match endpoint {
	Known(value) => match EdtfDate.from_description(value) {
		Ok(date) => EdtfDate.to_text(date)
		Err(_) => crash "EdtfInterval validates every known endpoint against EdtfDate"
	}
	Unknown => ""
	Open => ".."
}

# LOC sourced interval meanings are checked independently in public fixtures.
expect {
	unknown = EdtfInterval.parse("1985/")?
	open = EdtfInterval.parse("1985/..")?
	unknown != open and EdtfInterval.to_text(unknown) == "1985/" and
		CalendarInterval.endpoints(EdtfInterval.description(unknown)).end == Unknown and
			CalendarInterval.endpoints(EdtfInterval.description(open)).end == Open
}
expect {
	EdtfInterval.to_text(EdtfInterval.parse("/")?) == "/" and
		EdtfInterval.to_text(EdtfInterval.parse("../..")?) == "../.." and
			EdtfInterval.to_text(EdtfInterval.parse("/..")?) == "/.." and
				EdtfInterval.to_text(EdtfInterval.parse("../")?) == "../"
}
expect {
	EdtfInterval.parse("2005/2004") == Err(ReversedBounds) and
		EdtfInterval.parse("2005-03/2005-02") == Err(ReversedBounds) and
			EdtfInterval.parse("2005-02-02/2005-02-01") == Err(ReversedBounds) and
				EdtfInterval.to_text(EdtfInterval.parse("2005-02-02/2005-02")?) == "2005-02-02/2005-02" and
					EdtfInterval.to_text(EdtfInterval.parse("2005?/2004")?) == "2005?/2004"
}
expect {
	EdtfInterval.parse("1964") == Err(Incomplete) and
		EdtfInterval.parse("1964/2004-0") == Err(End(Incomplete)) and
			EdtfInterval.parse("1900-02-29/2000") == Err(Start(Malformed)) and
				EdtfInterval.parse("1985/156X") == Err(End(UnsupportedForm)) and
					EdtfInterval.parse("1985/2000/2001") == Err(Malformed) and
						EdtfInterval.parse("x".repeat(130)) == Err(TooLarge) and
							EdtfInterval.parse("${"x".repeat(65)}/") == Err(Start(TooLarge))
}
expect {
	a : EdtfInterval
	a = "?2004-06-11/2005-02"
	b = EdtfInterval.parse("2004?-06-11/2005-02")?
	a == b and Dict.get(Dict.insert(Dict.empty(), a, 1.U64), b) == Ok(1) and
		EdtfInterval.fact_at(a, U64.highest) == End
}

# LOC Time Interval examples 1..6 (2019-02-04 specification). Expected
# fields/resolutions are transcribed meanings, not generated by the serializer.
expect {
	cases = [
		{ text: "1964/2008", start: { year: 1964.I64, month: 1.U8, day: 1.U8, resolution: Year }, end: { year: 2008.I64, month: 1.U8, day: 1.U8, resolution: Year } },
		{ text: "2004-06/2006-08", start: { year: 2004, month: 6, day: 1, resolution: Month }, end: { year: 2006, month: 8, day: 1, resolution: Month } },
		{ text: "2004-02-01/2005-02-08", start: { year: 2004, month: 2, day: 1, resolution: Day }, end: { year: 2005, month: 2, day: 8, resolution: Day } },
		{ text: "2004-02-01/2005-02", start: { year: 2004, month: 2, day: 1, resolution: Day }, end: { year: 2005, month: 2, day: 1, resolution: Month } },
		{ text: "2004-02-01/2005", start: { year: 2004, month: 2, day: 1, resolution: Day }, end: { year: 2005, month: 1, day: 1, resolution: Year } },
		{ text: "2005/2006-02", start: { year: 2005, month: 1, day: 1, resolution: Year }, end: { year: 2006, month: 2, day: 1, resolution: Month } },
	]
	var $matches = True
	for case in cases {
		parts = CalendarInterval.endpoints(EdtfInterval.description(EdtfInterval.parse(case.text)?))
		for (endpoint, expected) in [(parts.start, case.start), (parts.end, case.end)] {
			match endpoint {
				Known(description) => {
					data = Calendar.Value.description(QualifiedCalendarValue.described_value(description))
					$matches = $matches and data.calendar == Gregorian and data.fields == { year: expected.year, month: expected.month, day: expected.day } and data.resolution == expected.resolution and QualifiedCalendarValue.qualifications(description).is_empty()
				}
				_ => {
					$matches = False
				}
			}
		}
	}
	$matches
}

# LOC Extended Interval examples 3,6,9,12 and Level 2 Interval example 1.
expect {
	var $matches = True
	for (text, role, state) in [("1985/..", End, Open), ("../1985", Start, Open), ("1985/", End, Unknown), ("/1985", Start, Unknown)] {
		parts = CalendarInterval.endpoints(EdtfInterval.description(EdtfInterval.parse(text)?))
		endpoint = if role == Start {
			parts.start
		} else {
			parts.end
		}
		other = if role == Start {
			parts.end
		} else {
			parts.start
		}
		$matches = $matches and endpoint == state
		match other {
			Known(description) => {
				data = Calendar.Value.description(QualifiedCalendarValue.described_value(description))
				$matches = $matches and data.resolution == Year and data.fields.year == 1985
			}
			_ => {
				$matches = False
			}
		}
	}
	qualified = CalendarInterval.endpoints(EdtfInterval.description(EdtfInterval.parse("2004-06-~01/2004-06-~20")?))
	for (endpoint, expected_day) in [(qualified.start, 1.U8), (qualified.end, 20)] {
		match endpoint {
			Known(description) => {
				data = Calendar.Value.description(QualifiedCalendarValue.described_value(description))
				$matches = $matches and data.fields == { year: 2004, month: 6, day: expected_day } and data.resolution == Day and QualifiedCalendarValue.qualifications(description) == [{ scope: Day, qualifier: Approximate }]
			}
			_ => {
				$matches = False
			}
		}
	}
	$matches
}

expect {
	# Grammar priority: no slash does not make invalid dates incomplete, while
	# a valid endpoint still needs its separator. Unsupported known forms retain
	# their side and do not become generic malformed interval errors.
	EdtfInterval.parse("") == Err(Incomplete) and
		EdtfInterval.parse("1900-02-29") == Err(Start(Malformed)) and
			EdtfInterval.parse("Y170000002") == Err(Start(UnsupportedForm)) and
				EdtfInterval.parse("1985/2004-99") == Err(End(Malformed)) and
					EdtfInterval.parse("1985/.") == Err(End(Incomplete)) and
						EdtfInterval.parse("1985/2004-02-") == Err(End(Incomplete)) and
							EdtfInterval.parse("x".repeat(64)) == Err(Start(Malformed))
}

expect {
	julian = QualifiedCalendarValue.new(Calendar.Value.year(Julian, 2004)?, [])?
	native = CalendarInterval.new({ start: Known(julian), end: Open })?
	negative = QualifiedCalendarValue.new(Calendar.Value.year(Gregorian, -1)?, [])?
	EdtfInterval.from_description(native) == Err(Start(UnsupportedCalendar)) and
		EdtfInterval.new({ start: Unknown, end: Known(negative) }) == Err(End(OutOfRange))
}

# R06/R13/R14. The inputs are pinned by tests/oracles/julian-manifest.toml
# and tests/oracles/gregorian-manifest.toml. Julian case 98 puts 1900-02-29
# at civil day -25496, twelve days beyond Gregorian case 60 (1900-03-01).
# Case 62 in each oracle puts their December 31 labels thirteen days apart,
# so Julian December 18 is the final day of Gregorian 1900.
expect {
	february = QualifiedCalendarValue.new(Calendar.Value.month(Julian, { year: 1900, month: 2 })?, [])?
	year = QualifiedCalendarValue.new(Calendar.Value.year(Gregorian, 1900)?, [])?
	var $valid = Bool.True
	for fixture in [
		{ calendar: Gregorian, month: 3.U8, day: 13.U8, end: Known(february), error: End(UnsupportedCalendar) },
		{ calendar: Julian, month: 12, day: 18, end: Known(year), error: Start(UnsupportedCalendar) },
	] {
		boundary = Calendar.Date.from_fields(fixture.calendar, { year: 1900, month: fixture.month, day: fixture.day })?
		later = Calendar.Date.from_fields(fixture.calendar, { year: 1900, month: fixture.month, day: fixture.day + 1 })?
		first = QualifiedCalendarValue.new(Calendar.Value.day(boundary), [])?
		too_late = QualifiedCalendarValue.new(Calendar.Value.day(later), [])?
		parts = { start: Known(first), end: fixture.end }
		native = CalendarInterval.new(parts)?
		$valid = $valid and CalendarInterval.endpoints(native) == parts and
			CalendarInterval.new({ start: Known(too_late), end: fixture.end }) == Err(ReversedBounds) and
				EdtfInterval.from_description(native) == Err(fixture.error)
	}
	$valid
}

expect {
	EdtfInterval.to_text(EdtfInterval.parse("0000-02-29/9999")?) == "0000-02-29/9999" and
		EdtfInterval.parse("0000-02-29/0000-02-29") != Err(ReversedBounds) and
			EdtfInterval.parse("${"x".repeat(64)}/${"x".repeat(64)}") == Err(Start(Malformed)) and
				EdtfInterval.parse("${"x".repeat(65)}/${"x".repeat(63)}") == Err(Start(TooLarge)) and
					EdtfInterval.parse("${"x".repeat(65)}/${"x".repeat(64)}") == Err(TooLarge)
}
