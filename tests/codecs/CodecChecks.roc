import time.Interchange.EdtfInterval as EdtfInterval
import time.Interchange.EdtfDate as EdtfDate
import time.OffsetTimestamp
import time.ExactInterval
import time.Interchange.Ixdtf as Ixdtf
import time.ICalendar.DateTime as ICalDateTime
import time.ICalendar.Duration as ICalDuration
import time.ICalendar.Period as ICalPeriod
import time.GregorianDate
import time.ClockTime
import time.Nanosecond.ClockTime as NanoClockTime
import time.LocalDateTime
import time.Calendar
# Real builtin JSON exercises derived record/list composition and format-level
# state handling. The second encoding below proves the hooks are format-generic.
# Strings are canonical standards declarations, never opaque native records.
CodecChecks := [].{
	Errors : [InvalidJson(Str), MissingRequiredField(Str)]
	Document : { date : EdtfDate, dates : List(EdtfDate), exact : ExactInterval, ixdtf : Ixdtf, rfc_date : ICalDateTime, rfc_duration : ICalDuration, rfc_period : ICalPeriod, stamp : OffsetTimestamp, tail : Str }
	run = |input| {
		check_interval_codecs(input.interval_invalid)
		check_civil(input.civil, input.civil_invalid_date, input.civil_invalid_clock)
		check_civil_tokens(input.civil_tokens)
		check_nano_clock(input.nano_clock, input.nano_clock_invalid)
		result : Try(Document, Errors)
		result = Json.parse(input.source)
		document = match result {
			Ok(value) => value
			Err(_) => crash "Semantic JSON document failed to parse"
		}
		encoded = Json.to_str(document)
		replay : Try(Document, Errors)
		replay = Json.parse(encoded)
		if encoded != input.canonical or replay != Ok(document) or document.tail != "kept" or document.dates.len() != 2 {
			crash "Semantic JSON encoding or nested parser state changed"
		}
		date : EdtfDate
		date = "1984?"
		stamp : OffsetTimestamp
		stamp = "2026-06-15T10:30:00.120Z"
		exact : ExactInterval
		exact = "2026-06-15T09:00:00Z/2026-06-15T10:00:00Z"
		ixdtf : Ixdtf
		ixdtf = "2022-07-08T00:14:07Z[Europe/Paris][u-ca=hebrew]"
		rfc_date : ICalDateTime
		rfc_date = "19970902T090000Z"
		rfc_duration : ICalDuration
		rfc_duration = "PT1H"
		rfc_period : ICalPeriod
		rfc_period = "19970902T090000Z/PT1H"
		if document.date != date or document.stamp != stamp or document.exact != exact or document.ixdtf != ixdtf or
			document.rfc_date != rfc_date or document.rfc_duration != rfc_duration or document.rfc_period != rfc_period {
			crash "Validated quoted literal differs from semantic JSON declaration"
		}
		# Runtime interpolation remains Str followed by explicit fallible parse.
		dynamic = EdtfDate.parse("${input.year}-02-29")
		if (
			match dynamic {
				Ok(value) => EdtfDate.to_text(value) == "2020-02-29"
				Err(_) => Bool.False
			}
		) == Bool.False {
			crash "Explicit interpolated parse failed"
		}
		invalid_date : Try(EdtfDate, Errors)
		invalid_date = Json.parse(input.invalid_date)
		if invalid_date != Err(InvalidJson("Invalid JSON")) {
			crash "EDTF JSON validation failure was not reported"
		}
		invalid_stamp : Try(OffsetTimestamp, Errors)
		invalid_stamp = Json.parse(input.invalid_stamp)
		if invalid_stamp != Err(InvalidJson("Invalid JSON")) {
			crash "Timestamp JSON validation failure was not reported"
		}
		invalid_exact : Try(ExactInterval, Errors)
		invalid_exact = Json.parse(input.invalid_exact)
		if invalid_exact != Err(InvalidJson("Invalid JSON")) {
			crash "Exact interval JSON validation failure was not reported"
		}
		invalid_ixdtf : Try(Ixdtf, Errors)
		invalid_ixdtf = Json.parse(input.invalid_ixdtf)
		if invalid_ixdtf != Err(InvalidJson("Invalid JSON")) {
			crash "IXDTF JSON validation failure was not reported"
		}
		invalid_rfc_date : Try(ICalDateTime, Errors)
		invalid_rfc_date = Json.parse(input.invalid_rfc_date)
		if invalid_rfc_date != Err(InvalidJson("Invalid JSON")) {
			crash "RFC datetime JSON validation failure was not reported"
		}
		invalid_duration : Try(ICalDuration, Errors)
		invalid_duration = Json.parse(input.invalid_duration)
		if invalid_duration != Err(InvalidJson("Invalid JSON")) {
			crash "RFC duration JSON validation failure was not reported"
		}
		invalid_period : Try(ICalPeriod, Errors)
		invalid_period = Json.parse(input.invalid_period)
		if invalid_period != Err(InvalidJson("Invalid JSON")) {
			crash "RFC period JSON validation failure was not reported"
		}
		syntax : Try(Document, Errors)
		syntax = Json.parse(input.syntax)
		match syntax {
			Err(InvalidJson("Invalid JSON")) => {}
			_ => crash "Malformed JSON did not retain format error"
		}
		backing : Try(EdtfDate, Errors)
		backing = Json.parse(input.backing)
		match backing {
			Err(InvalidJson(_)) => {}
			_ => crash "Opaque backing record accepted instead of semantic string"
		}
		nested_bad : Try({ dates : List(EdtfDate), tail : Str }, Errors)
		nested_bad = Json.parse(input.nested_bad)
		match nested_bad {
			Err(InvalidJson("Invalid JSON")) => {}
			_ => crash "Nested list did not report validation failure"
		}
		invalid_stamp_text : Str
		invalid_stamp_text = Json.parse(input.invalid_stamp) ?? crash "Invalid timestamp fixture is not a JSON string"
		invalid_clock_text : Str
		invalid_clock_text = Json.parse(input.civil_invalid_clock) ?? crash "Invalid clock fixture is not a JSON string"
		invalid_duration_text : Str
		invalid_duration_text = Json.parse(input.invalid_duration) ?? crash "Invalid duration fixture is not a JSON string"
		if OffsetTimestamp.parse(invalid_stamp_text) != Err(InvalidDate) or
			ClockTime.parse(invalid_clock_text) != Err(UnsupportedLeapSecond) or
				ICalDuration.parse(invalid_duration_text) != Err(NonPositive) {
			crash "Direct temporal parsers lost detailed validation errors"
		}
		check_tokens(input.tokens, date)
	}
}

CivilErrors : [InvalidJson(Str), MissingRequiredField(Str)]

CivilDocument : { date : GregorianDate, clock : ClockTime, tail : Str }

check_civil = |source, invalid_date, invalid_clock| {
	parsed : Try(CivilDocument, CivilErrors)
	parsed = Json.parse(source)
	value = match parsed {
		Ok(record) => record
		Err(_) => crash "Civil appointment record rejected"
	}
	date : GregorianDate
	date = "2026-09-07"
	clock : ClockTime
	clock = "09:30"
	if value != { date, clock, tail: "kept" } or
		Json.to_str(value) != "{\"clock\":\"09:30:00\",\"date\":\"2026-09-07\",\"tail\":\"kept\"}" {
		crash "Civil record text changed date/clock meaning or exposed backing fields"
	}
	local = LocalDateTime.new({ date: Calendar.Date.from_gregorian(value.date), clock: value.clock })
	if LocalDateTime.parse_gregorian("2026-09-07T09:30") != Ok(local) or
		LocalDateTime.to_gregorian_text(local) != Ok("2026-09-07T09:30:00") {
		crash "Civil record did not compose into an unzoned local appointment"
	}
	bad_date : Try(GregorianDate, CivilErrors)
	bad_date = Json.parse(invalid_date)
	bad_clock : Try(ClockTime, CivilErrors)
	bad_clock = Json.parse(invalid_clock)
	if bad_date != Err(InvalidJson("Invalid JSON")) or bad_clock != Err(InvalidJson("Invalid JSON")) {
		crash "Civil JSON codecs did not report validation failures"
	}
}

NanoDocument : { clock : NanoClockTime, tail : Str }

# JSON and the token encoding carry all nine fractional digits; a tenth digit
# is a format-level validation failure, while parse keeps the detailed error.
check_nano_clock = |source, invalid| {
	parsed : Try(NanoDocument, CivilErrors)
	parsed = Json.parse(source)
	clock : NanoClockTime
	clock = "12:00:00.000000001"
	if parsed != Ok({ clock, tail: "kept" }) or
		Json.to_str({ clock, tail: "kept" }) != "{\"clock\":\"12:00:00.000000001\",\"tail\":\"kept\"}" {
		crash "Nanosecond clock record text changed meaning or exposed backing fields"
	}
	bad : Try(NanoClockTime, CivilErrors)
	bad = Json.parse(invalid)
	invalid_text : Str
	invalid_text = Json.parse(invalid) ?? crash "Invalid nanosecond clock fixture is not a JSON string"
	if bad != Err(InvalidJson("Invalid JSON")) or NanoClockTime.parse(invalid_text) != Err(UnsupportedPrecision) {
		crash "Nanosecond clock codec did not report validation failure"
	}
	parse_clock = NanoClockTime.parser_for(TokenEncoding.Default)
	encode_clock = NanoClockTime.encoder_for(TokenEncoding.Default)
	match parse_clock(["12:00:00.000000001", "tail"]) {
		Ok(found) => if found.value != clock or found.rest != ["tail"] {
			crash "Nanosecond clock parser changed value or unconsumed state"
		}
		Err(_) => crash "Nanosecond clock token rejected"
	}
	if parse_clock([]) != Err(NoToken) or
		encode_clock(clock, ["prefix"]) != Ok(["prefix", "12:00:00.000000001"]) or
			encode_clock(clock, ["full", "buffer"]) != Err(WriteBlocked) {
		crash "Nanosecond clock token codec lost state or encoding failure"
	}
}

TokenEncoding := [Default].{
	invalid_value : TokenEncoding, List(Str) -> [NoToken, InvalidToken]
	invalid_value = |_, _| InvalidToken

	parse_str : TokenEncoding, List(Str) -> Try({ value : Str, rest : List(Str) }, [NoToken, InvalidToken])
	parse_str = |_, state| match state.first() {
		Ok(value) => Ok({ value, rest: state.drop_first(1) })
		Err(_) => Err(NoToken)
	}
	encode_str : Str, List(Str) -> Try(List(Str), [WriteBlocked])
	encode_str = |text, state| if state.len() >= 2 {
		Err(WriteBlocked)
	} else {
		Ok(state.append(text))
	}
}

check_civil_tokens = |tokens| {
	parse_date = GregorianDate.parser_for(TokenEncoding.Default)
	first = match parse_date(tokens) {
		Ok(value) => value
		Err(_) => crash "Civil date token rejected"
	}
	parse_clock = ClockTime.parser_for(TokenEncoding.Default)
	second = match parse_clock(first.rest) {
		Ok(value) => value
		Err(_) => crash "Civil clock token rejected"
	}
	if GregorianDate.to_text(first.value) != "2026-09-07" or
		ClockTime.to_text(second.value) != "09:30:00" or second.rest != ["tail"] {
		crash "Civil parser changed semantic values or unconsumed state"
	}
	match parse_date([]) {
		Err(NoToken) => {}
		_ => crash "Civil date parser lost encoding failure"
	}
	match parse_clock([]) {
		Err(NoToken) => {}
		_ => crash "Civil clock parser lost encoding failure"
	}
	encode_date = GregorianDate.encoder_for(TokenEncoding.Default)
	encode_clock = ClockTime.encoder_for(TokenEncoding.Default)
	if encode_date(first.value, ["prefix"]) != Ok(["prefix", "2026-09-07"]) or
		encode_date(first.value, ["full", "buffer"]) != Err(WriteBlocked) or
			encode_clock(second.value, ["prefix"]) != Ok(["prefix", "09:30:00"]) or
				encode_clock(second.value, ["full", "buffer"]) != Err(WriteBlocked) {
		crash "Civil encoder changed state or lost encoding failure"
	}
}

check_tokens = |tokens, expected| {
	parse = EdtfDate.parser_for(TokenEncoding.Default)
	first = match parse(tokens) {
		Ok(value) => value
		Err(_) => crash "Generic token encoding parse failed"
	}
	second = match parse(first.rest) {
		Ok(value) => value
		Err(_) => crash "Generic token encoding continuation failed"
	}
	if first.value != expected or EdtfDate.to_text(second.value) != "2020-02-29" or second.rest != ["tail"] {
		crash "Generic parser changed unconsumed encoding state"
	}
	if parse(["not-a-date"]) != Err(InvalidToken) {
		crash "Generic codec did not use the format-owned validation error"
	}
	match parse([]) {
		Err(NoToken) => {}
		_ => crash "Generic encoding error was not preserved"
	}
	encode = EdtfDate.encoder_for(TokenEncoding.Default)
	if encode(first.value, ["prefix"]) != Ok(["prefix", "1984?"]) or
		encode(first.value, ["full", "buffer"]) != Err(WriteBlocked) {
		crash "Generic semantic encoder lost state or format failure"
	}
}

IntervalErrors : [InvalidJson(Str), MissingRequiredField(Str)]

check_interval_codecs = |invalid| {
	value : EdtfInterval
	value = "?2004-06-11/2005-02"
	parsed : Try({ items : List(EdtfInterval), tail : Str }, IntervalErrors)
	parsed = Json.parse("{\"items\":[\"2004?-06-11/2005-02\",\"1985/..\",\"1985/\"],\"tail\":\"kept\"}")
	record = parsed ?? crash "EDTF interval JSON list rejected"
	if record.items.first() != Ok(value) or record.tail != "kept" {
		crash "EDTF interval codec lost declaration or parser state"
	}
	replay : Try({ items : List(EdtfInterval), tail : Str }, IntervalErrors)
	replay = Json.parse(Json.to_str(record))
	if replay != Ok(record) {
		crash "EDTF interval semantic JSON round trip changed knowledge states"
	}
	bad : Try(EdtfInterval, IntervalErrors)
	bad = Json.parse(invalid)
	if bad != Err(InvalidJson("Invalid JSON")) {
		crash "Interval JSON validation failure was not reported"
	}
	parse = EdtfInterval.parser_for(TokenEncoding.Default)
	first = parse(["1985/", "tail"]) ?? crash "Generic interval codec rejected date interval"
	if first.rest != ["tail"] {
		crash "Generic interval codec consumed trailing state"
	}
	encode = EdtfInterval.encoder_for(TokenEncoding.Default)
	if encode(first.value, []) != Ok(["1985/"]) {
		crash "Generic interval codec did not encode standard text"
	}
}
