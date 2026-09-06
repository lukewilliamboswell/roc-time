import time.EdtfDate
import time.OffsetTimestamp
import time.ExactInterval
import time.Ixdtf
import time.RfcDateTime
import time.RfcDuration
import time.RfcPeriod

# Real builtin JSON exercises derived record/list composition and format-level
# state handling. The second encoding below proves the hooks are format-generic.
# Strings are canonical standards declarations, never opaque native records.
CodecChecks := [].{
	Errors : [InvalidJson(Str), MissingRequiredField(Str), Encoding([InvalidJson(Str)]), InvalidEdtfDate(EdtfDate.Error), InvalidOffsetTimestamp(OffsetTimestamp.Error), InvalidExactInterval(ExactInterval.Error), InvalidIxdtf(Ixdtf.Error), InvalidRfcDateTime(RfcDateTime.Error), InvalidRfcDuration(RfcDuration.Error), InvalidRfcPeriod(RfcPeriod.Error)]
	Document : { date : EdtfDate, dates : List(EdtfDate), exact : ExactInterval, ixdtf : Ixdtf, rfc_date : RfcDateTime, rfc_duration : RfcDuration, rfc_period : RfcPeriod, stamp : OffsetTimestamp, tail : Str }
	run = |input| {
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
		rfc_date : RfcDateTime
		rfc_date = "19970902T090000Z"
		rfc_duration : RfcDuration
		rfc_duration = "PT1H"
		rfc_period : RfcPeriod
		rfc_period = "19970902T090000Z/PT1H"
		if document.date != date or document.stamp != stamp or document.exact != exact or document.ixdtf != ixdtf or
			document.rfc_date != rfc_date or document.rfc_duration != rfc_duration or document.rfc_period != rfc_period {
			crash "Validated quoted literal differs from semantic JSON declaration"
		}
		# Runtime interpolation remains Str followed by explicit fallible parse.
		dynamic = EdtfDate.parse("${input.year}-02-29")
		if (match dynamic {
			Ok(value) => EdtfDate.to_text(value) == "2020-02-29"
			Err(_) => Bool.False
		}) == Bool.False {
			crash "Explicit interpolated parse failed"
		}
		invalid_date : Try(EdtfDate, Errors)
		invalid_date = Json.parse(input.invalid_date)
		if invalid_date != Err(InvalidEdtfDate(Malformed)) {
			crash "Lost EDTF semantic error"
		}
		invalid_stamp : Try(OffsetTimestamp, Errors)
		invalid_stamp = Json.parse(input.invalid_stamp)
		if invalid_stamp != Err(InvalidOffsetTimestamp(InvalidDate)) {
			crash "Lost timestamp semantic error"
		}
		invalid_exact : Try(ExactInterval, Errors)
		invalid_exact = Json.parse(input.invalid_exact)
		if invalid_exact != Err(InvalidExactInterval(EmptySpan)) {
			crash "Lost exact interval semantic error"
		}
		invalid_ixdtf : Try(Ixdtf, Errors)
		invalid_ixdtf = Json.parse(input.invalid_ixdtf)
		if invalid_ixdtf != Err(InvalidIxdtf(UnknownCritical)) {
			crash "Lost IXDTF semantic error"
		}
		invalid_rfc_date : Try(RfcDateTime, Errors)
		invalid_rfc_date = Json.parse(input.invalid_rfc_date)
		if invalid_rfc_date != Err(InvalidRfcDateTime(InvalidDate)) {
			crash "Lost RFC datetime semantic error"
		}
		invalid_duration : Try(RfcDuration, Errors)
		invalid_duration = Json.parse(input.invalid_duration)
		if invalid_duration != Err(InvalidRfcDuration(NonPositive)) {
			crash "Lost RFC duration semantic error"
		}
		invalid_period : Try(RfcPeriod, Errors)
		invalid_period = Json.parse(input.invalid_period)
		if invalid_period != Err(InvalidRfcPeriod(InvalidPeriod)) {
			crash "Lost RFC period semantic error"
		}
		syntax : Try(Document, Errors)
		syntax = Json.parse(input.syntax)
		match syntax {
			Err(InvalidJson(_)) => {}
			_ => crash "Malformed JSON did not retain format error"
		}
		backing : Try(EdtfDate, Errors)
		backing = Json.parse(input.backing)
		match backing {
			Err(Encoding(InvalidJson(_))) => {}
			_ => crash "Opaque backing record accepted instead of semantic string"
		}
		nested_bad : Try({ dates : List(EdtfDate), tail : Str }, Errors)
		nested_bad = Json.parse(input.nested_bad)
		match nested_bad {
			Err(InvalidEdtfDate(Malformed)) => {}
			_ => crash "Nested list lost semantic validation error"
		}
		check_tokens(input.tokens, date)
	}
}

TokenEncoding := [Default].{
	parse_str : TokenEncoding, List(Str) -> Try({ value : Str, rest : List(Str) }, [NoToken])
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
	match parse([]) {
		Err(Encoding(NoToken)) => {}
		_ => crash "Generic encoding error was not preserved"
	}
	encode = EdtfDate.encoder_for(TokenEncoding.Default)
	if encode(first.value, ["prefix"]) != Ok(["prefix", "1984?"]) or
		encode(first.value, ["full", "buffer"]) != Err(WriteBlocked) {
		crash "Generic semantic encoder lost state or format failure"
	}
}
