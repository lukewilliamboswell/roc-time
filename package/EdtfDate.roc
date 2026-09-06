import SemanticFact
import CalendarValue
import QualifiedCalendarValue
import CalendarDate
import LocalDateTime

## EDTF date-only profile edtf-gregorian-date-v1: YYYY[-MM[-DD]][?~%].
## Four ASCII year digits use Gregorian astronomical years 0000..9999.
## Each omitted component preserves reduced resolution. One trailing qualifier
## applies to Whole; it does not supply a tolerance or resolve a timezone.
## This subset is not EDTF Level 0 conformance, which also requires timestamps
## and intervals. No source spelling or native persistence format is promised.
##
## Source: Library of Congress EDTF published specification, February 4, 2019,
## https://www.loc.gov/standards/datetime/ (accessed 2026-09-06), Level 0 Date
## and Level 1 Qualification of a date (complete). Unit fixtures below transcribe
## example meanings; expected fields are independent of parsing/serialization.
##
## Parsing is bounded by 64 UTF-8 bytes. Valid partial grammar prefixes return
## Incomplete. Invalid fields/grammar return Malformed. Selected recognized
## excluded forms (negative year, long year, year-only mask) return UnsupportedForm;
## recognition does not validate every excluded EDTF feature. Native conversion
## checks calendar, resolution, year range and qualifier scope explicitly.
##
## Generic codecs use canonical strings and typed literals validate at compile time:
## ```roc
## import time.EdtfDate
## expect {
##     date : EdtfDate
##     date = "1984?"
##     parsed : Try({ date : EdtfDate }, [InvalidJson(Str), MissingRequiredField(Str), Encoding([InvalidJson(Str)]), InvalidEdtfDate(EdtfDate.Error)])
##     parsed = Json.parse(Json.to_str({ date: date }))
##     parsed == Ok({ date: date })
## }
## ```
EdtfDate :: { raw : QualifiedCalendarValue }.{
	Error : [Malformed, Incomplete, TooLarge, OutOfRange, UnsupportedForm, UnsupportedCalendar, UnsupportedResolution, UnsupportedQualification]

	## Generic encodings carry canonical text, never the opaque backing record.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : EdtfDate, rest : state }, [InvalidEdtfDate(Error), Encoding(err), ..]))
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
				Err(error) => Err(InvalidEdtfDate(error))
			}
		}
	}

	encoder_for : encoding -> (EdtfDate, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(EdtfDate, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid EdtfDate literal: ${Str.inspect(error)}"))
	}

	profile : Str
	profile = "edtf-gregorian-date-v1"
	parse : Str -> Try(EdtfDate, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		if excluded(bytes) {
			return Err(UnsupportedForm)
		}
		qualifier = match bytes.last() {
			Ok(63) => [{ scope: Whole, qualifier: Uncertain }]
			Ok(126) => [{ scope: Whole, qualifier: Approximate }]
			Ok(37) => [{ scope: Whole, qualifier: UncertainApproximate }]
			_ => []
		}
		size = bytes.len() - (
			if qualifier.is_empty() {
				0
			} else {
				1
			}
		)
		core = bytes.sublist({ start: 0, len: size })
		var index = 0.U64
		for byte in core {
			valid = if index == 4 or index == 7 {
				byte == 45
			} else {
				index < 10 and digit(byte)
			}
			if !valid {
				return Err(Malformed)
			}
			index = index + 1
		}
		# Incomplete means a prefix can still become a valid accepted date.
		# Validate complete higher fields and partial digit feasibility first.
		if size == 6 and digits(core, 5, 1) > 1 {
			return Err(Malformed)
		}
		if size >= 7 {
			prefix_year = digits(core, 0, 4).to_i64()
			prefix_month = digits(core, 5, 2).to_u8_wrap()
			match CalendarValue.month(Gregorian, prefix_year, prefix_month) {
				Ok(_) => {}
				Err(_) => return Err(Malformed)
			}
			if size == 9 {
				tens = digits(core, 8, 1).to_u8_wrap() * 10
				var possible = Bool.False
				var digit_value = 0.U8
				while digit_value < 10 {
					match CalendarDate.from_fields(Gregorian, { year: prefix_year, month: prefix_month, day: tens + digit_value }) {
						Ok(_) => {
							possible = True
						}
						Err(_) => {}
					}
					digit_value = digit_value + 1
				}
				if !possible {
					return Err(Malformed)
				}
			}
		}
		if size != 4 and size != 7 and size != 10 {
			return if qualifier.is_empty() and size < 10 {
				Err(Incomplete)
			} else {
				Err(Malformed)
			}
		}
		year = digits(core, 0, 4).to_i64()
		value = if size == 4 {
			match CalendarValue.year(Gregorian, year) {
				Ok(v) => v
				Err(_) => return Err(OutOfRange)
			}
		} else {
			month = digits(core, 5, 2).to_u8_wrap()
			if size == 7 {
				match CalendarValue.month(Gregorian, year, month) {
					Ok(v) => v
					Err(_) => return Err(Malformed)
				}
			} else {
				date = match CalendarDate.from_fields(Gregorian, { year, month, day: digits(core, 8, 2).to_u8_wrap() }) {
					Ok(v) => v
					Err(_) => return Err(Malformed)
				}
				CalendarValue.day(date)
			}
		}
		raw = match QualifiedCalendarValue.new(value, qualifier) {
			Ok(v) => v
			Err(_) => crash "Parser constructs at most one Whole qualification"
		}
		Ok({ raw: raw })
	}
	from_description : QualifiedCalendarValue -> Try(EdtfDate, Error)
	from_description = |raw| {
		value = QualifiedCalendarValue.described_value(raw)
		date = LocalDateTime.date(CalendarValue.start_label(value))
		if CalendarDate.calendar(date) != Gregorian {
			return Err(UnsupportedCalendar)
		}
		match CalendarValue.resolution(value) {
			Year => {}
			Month => {}
			Day => {}
			_ => return Err(UnsupportedResolution)
		}
		year = CalendarDate.to_fields(date).year
		if year < 0 or year > 9999 {
			return Err(OutOfRange)
		}
		for q in QualifiedCalendarValue.qualifications(raw) {
			if q.scope != Whole {
				return Err(UnsupportedQualification)
			}
		}
		Ok({ raw: raw })
	}
	description : EdtfDate -> QualifiedCalendarValue
	description = |value| value.raw
	to_text : EdtfDate -> Str
	to_text = |wrapped| {
		raw = wrapped.raw
		value = QualifiedCalendarValue.described_value(raw)
		fields = CalendarDate.to_fields(LocalDateTime.date(CalendarValue.start_label(value)))
		year = pad(fields.year.to_str(), 4)
		date = match CalendarValue.resolution(value) {
			Year => year
			Month => "${year}-${pad(fields.month.to_str(), 2)}"
			Day => "${year}-${pad(fields.month.to_str(), 2)}-${pad(fields.day.to_str(), 2)}"
			_ => crash "EdtfDate validates date-only resolution"
		}
		suffix = match QualifiedCalendarValue.qualifications(raw).first() {
			Err(_) => ""
			Ok(q) => match q.qualifier {
				Uncertain => "?"
				Approximate => "~"
				UncertainApproximate => "%"
			}
		}
		"${date}${suffix}"
	}
	is_eq : EdtfDate, EdtfDate -> Bool
	is_eq = |a, b| QualifiedCalendarValue.is_eq(a.raw, b.raw)
	to_hash : EdtfDate, Hasher -> Hasher
	to_hash = |value, hasher| QualifiedCalendarValue.to_hash(value.raw, hasher)
	fact_count : EdtfDate -> U64
	fact_count = |value| QualifiedCalendarValue.fact_count(value.raw)
	fact_at : EdtfDate, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| match QualifiedCalendarValue.fact_at(value.raw, index) {
		End => End
		Item(fact) => if index == 0 {
			match SemanticFact.kind(fact) {
				CalendarDescription(data) => Item(SemanticFact.new(CalendarDescription({ ..data, kind: EdtfDate })))
				_ => crash "QualifiedCalendarValue index zero is its calendar summary"
			}
		} else {
			Item(fact)
		}
	}
	to_inspect : EdtfDate -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "EdtfDate always has a summary at index zero"
	}
}

digit = |byte| byte >= 48 and byte <= 57

# Deliberately narrow recognition; arbitrary non-profile strings are not
# labelled valid unsupported syntax merely because they contain a marker.
excluded : List(U8) -> Bool
excluded = |bytes| {
	if bytes.len() == 5 and bytes.first() == Ok(45) {
		return bytes.sublist({ start: 1, len: 4 }).all(digit)
	}
	if bytes.len() >= 6 and bytes.first() == Ok(89) {
		rest = bytes.sublist({ start: 1, len: bytes.len() - 1 })
		unsigned = if rest.first() == Ok(45) {
			rest.sublist({ start: 1, len: rest.len() - 1 })
		} else {
			rest
		}
		return unsigned.len() > 4 and unsigned.first() != Ok(48) and unsigned.all(digit)
	}
	bytes.len() == 4 and bytes.contains(88) and bytes.all(|b| digit(b) or b == 88)
}

# Caller has validated positions and at most four ASCII digits.
digits : List(U8), U64, U64 -> U16
digits = |bytes, start, len| {
	var result = 0.U16
	for b in bytes.sublist({ start, len }) {
		result = result * 10 + (b - 48).to_u16()
	}
	result
}

pad = |text, width| "${"0".repeat(width - text.count_utf8_bytes())}${text}"

# LOC Level 0 Date examples; fields/resolution are sourced expectations.
expect {
	value = QualifiedCalendarValue.described_value(EdtfDate.description(EdtfDate.parse("1985-04-12")?))
	CalendarValue.resolution(value) == Day and CalendarDate.to_fields(LocalDateTime.date(CalendarValue.start_label(value))) == { year: 1985, month: 4, day: 12 }
}
expect {
	year = CalendarValue.year(Gregorian, 1985)?
	month = CalendarValue.month(Gregorian, 1985, 4)?
	QualifiedCalendarValue.described_value(EdtfDate.description(EdtfDate.parse("1985")?)) == year and QualifiedCalendarValue.described_value(EdtfDate.description(EdtfDate.parse("1985-04")?)) == month
}
expect {
	# LOC Level 1 qualification examples: independently specified Whole scope.
	a = EdtfDate.description(EdtfDate.parse("1984?")?)
	b = EdtfDate.description(EdtfDate.parse("2004-06~")?)
	c = EdtfDate.description(EdtfDate.parse("2004-06-11%")?)
	QualifiedCalendarValue.qualifications(a) == [{ scope: Whole, qualifier: Uncertain }] and QualifiedCalendarValue.qualifications(b) == [{ scope: Whole, qualifier: Approximate }] and QualifiedCalendarValue.qualifications(c) == [{ scope: Whole, qualifier: UncertainApproximate }]
}
expect {
	EdtfDate.parse("1900-02-29") == Err(Malformed) and EdtfDate.parse("1984?~") == Err(Malformed) and EdtfDate.parse("1985-0") == Err(Incomplete) and EdtfDate.parse("1985-0?") == Err(Malformed) and EdtfDate.parse("1985-04-12x") == Err(Malformed) and EdtfDate.parse("1985-13") == Err(Malformed) and EdtfDate.parse("1985-04-00") == Err(Malformed) and EdtfDate.parse("1985-04-31") == Err(Malformed)
}
expect {
	EdtfDate.to_text(EdtfDate.parse("0000-02-29%")?) == "0000-02-29%" and EdtfDate.to_text(EdtfDate.parse("9999")?) == "9999" and EdtfDate.parse("1985-04") != EdtfDate.parse("1985-04-01")
}
expect {
	EdtfDate.parse("156X") == Err(UnsupportedForm) and EdtfDate.parse("Y170000002") == Err(UnsupportedForm) and EdtfDate.parse("-1985") == Err(UnsupportedForm) and EdtfDate.parse("Yhello") == Err(Malformed) and EdtfDate.parse("x".repeat(65)) == Err(TooLarge)
}
expect {
	value = CalendarValue.month(Gregorian, 2004, 6)?
	scoped = QualifiedCalendarValue.new(value, [{ scope: Month, qualifier: Approximate }])?
	negative = QualifiedCalendarValue.new(CalendarValue.year(Gregorian, -1)?, [])?
	julian = QualifiedCalendarValue.new(CalendarValue.year(Julian, 2004)?, [])?
	EdtfDate.from_description(scoped) == Err(UnsupportedQualification) and EdtfDate.from_description(negative) == Err(OutOfRange) and EdtfDate.from_description(julian) == Err(UnsupportedCalendar)
}

expect EdtfDate.parse("1985-99-") == Err(Malformed) and EdtfDate.parse("1985-04-4") == Err(Malformed) and EdtfDate.parse("1985-04-3") == Err(Incomplete) and EdtfDate.parse("1985-9") == Err(Malformed)

expect {
	date = EdtfDate.parse("1984?")?
	match EdtfDate.fact_at(date, 0) {
		Item(fact) => match SemanticFact.kind(fact) {
			CalendarDescription(data) => data.kind == EdtfDate and data.resolution == Year and data.fields.year == 1984 and data.qualification_count == 1 and EdtfDate.fact_at(date, EdtfDate.fact_count(date)) == End
			_ => False
		}
		End => False
	}
}
