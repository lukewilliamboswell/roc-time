import PersistenceEnvelope
import EdtfDate
import OffsetTimestamp
import ExactInterval
import Ixdtf
import RfcDateTime
import RfcDuration
import RfcPeriod
import PosixBoundary
import PosixDelta
import PosixSpan
import Coverage

## Version 1 native persistence for seven supported text declarations and exact
## POSIX boundary/displacement/span/coverage values. The JSON envelope has seven required
## string fields: format, version, kind, profile, axis, unit and payload.
## Format is roc-time; version is 1. Unknown metadata errors before temporal
## payload interpretation. No private records or compiler union encoding leak.
##
## Text declarations use their declared canonical semantic text/profile and
## axis/unit none: they are source declarations, not resolved snapshots. This
## preserves resolution, qualifiers, UTC/local forms and ordered annotations;
## original spelling is not preserved. Decode never fetches context or resolves
## zones. Snapshot/rule/event/calendar-native persistence is outside
## this initial profile and unsupported kinds fail explicitly.
##
## Core kinds posix-boundary and posix-delta use profile posix-microseconds-v1,
## axis posix-1970, unit microsecond. Their payload is a canonical signed decimal
## STRING, including either I64 limit: no JSON floating-point precision loss.
## A delta is coordinate displacement, not physical elapsed SI time.
##
## Envelope decoding is bounded to 65536 encoded bytes and seven string fields.
## Span payloads use start/end signed decimals (posix-half-open-span-v1).
## Coverage payloads join canonical spans with semicolons (posix-canonical-coverage-v1);
## empty text means empty coverage. Input must be strictly ordered, disjoint and
## non-touching. This native payload grammar is not ISO interval syntax.
## These profiles use axis posix-1970 and unit microsecond. Missing endpoints
## return IncompleteSpan; malformed separators or integers remain distinct.
## Construction accepts at most 1024 coverage members, preserving all or failing.
## Decode counts members before allocating/parsing their spans, so an input
## above 1024 members errors before content/canonical-order validation. Canonical output
## fits below 44000 bytes: each pair needs at most 41 bytes plus one separator.
## Coverage encoding/decoding is linear in members plus text bytes; joins avoid
## repeated growing string appends. Input storage and output are materialized.
## Encoding does not interpret descriptions or enumerate temporal domains.
## Generic parser_for/encoder_for hooks are intentionally unsupported: use
## parse/to_text for the versioned envelope. Generic JSON must not derive the
## private Value representation or mistake it for this persistence contract.
##
## ```roc
## import time.Persistence
## import time.Coverage
## import time.PosixSpan
## import time.PosixBoundary
## expect {
##     first = PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(1))?
##     second = PosixSpan.new(PosixBoundary.from_microseconds(2), PosixBoundary.from_microseconds(3))?
##     stored = Persistence.new(Coverage(Coverage.from_spans([first, second])))?
##     restored = Persistence.parse(Persistence.to_text(stored))?
##     match Persistence.value(restored) {
##         Coverage(coverage) => !Coverage.contains(coverage, PosixBoundary.from_microseconds(1))
##         _ => False
##     }
## }
## ```
Persistence :: { stored : Value }.{
	Value : [EdtfDate(EdtfDate), OffsetTimestamp(OffsetTimestamp), ExactInterval(ExactInterval), Ixdtf(Ixdtf), RfcDateTime(RfcDateTime), RfcDuration(RfcDuration), RfcPeriod(RfcPeriod), PosixBoundary(PosixBoundary), PosixDelta(PosixDelta), PosixSpan(PosixSpan), Coverage(Coverage)]
	Error : [Envelope(PersistenceEnvelope.Error), UnknownFormat(Str), UnknownVersion(Str), UnknownKind(Str), UnsupportedProfile(Str), UnsupportedAxis(Str), UnsupportedUnit(Str), InvalidEdtfDate(EdtfDate.Error), InvalidOffsetTimestamp(OffsetTimestamp.Error), InvalidExactInterval(ExactInterval.Error), InvalidIxdtf(Ixdtf.Error), InvalidRfcDateTime(RfcDateTime.Error), InvalidRfcDuration(RfcDuration.Error), InvalidRfcPeriod(RfcPeriod.Error), InvalidInteger, OutOfRange, MalformedSpan, IncompleteSpan, InvalidSpan([EmptySpan, ReversedBounds]), NonCanonicalCoverage, TooManyMembers]
	new : Value -> Try(Persistence, [TooManyMembers, ..])
	new = |stored| {
		match stored {
			Coverage(coverage) => if Coverage.member_count(coverage) > 1024 {
				return Err(TooManyMembers)
			}
			_ => {}
		}
		Ok({ stored: stored })
	}
	value : Persistence -> Value
	value = |wrapped| wrapped.stored

	parse : Str -> Try(Persistence, Error)
	parse = |text| {
		envelope = match PersistenceEnvelope.parse(text) {
			Ok(inner) => inner
			Err(error) => return Err(Envelope(error))
		}
		fields = PersistenceEnvelope.fields(envelope)
		if fields.format != "roc-time" {
			return Err(UnknownFormat(fields.format))
		}
		if fields.version != "1" {
			return Err(UnknownVersion(fields.version))
		}
		expected = match metadata(fields.kind) {
			None => return Err(UnknownKind(fields.kind))
			Some(inner) => inner
		}
		if fields.profile != expected.profile {
			return Err(UnsupportedProfile(fields.profile))
		}
		if fields.axis != expected.axis {
			return Err(UnsupportedAxis(fields.axis))
		}
		if fields.unit != expected.unit {
			return Err(UnsupportedUnit(fields.unit))
		}
		stored = match fields.kind {
			"edtf-date" => match EdtfDate.parse(fields.payload) {
				Ok(inner) => EdtfDate(inner)
				Err(error) => return Err(InvalidEdtfDate(error))
			}
			"offset-timestamp" => match OffsetTimestamp.parse(fields.payload) {
				Ok(inner) => OffsetTimestamp(inner)
				Err(error) => return Err(InvalidOffsetTimestamp(error))
			}
			"exact-interval" => match ExactInterval.parse(fields.payload) {
				Ok(inner) => ExactInterval(inner)
				Err(error) => return Err(InvalidExactInterval(error))
			}
			"ixdtf" => match Ixdtf.parse(fields.payload) {
				Ok(inner) => Ixdtf(inner)
				Err(error) => return Err(InvalidIxdtf(error))
			}
			"rfc-date-time" => match RfcDateTime.parse(fields.payload) {
				Ok(inner) => RfcDateTime(inner)
				Err(error) => return Err(InvalidRfcDateTime(error))
			}
			"rfc-duration" => match RfcDuration.parse(fields.payload) {
				Ok(inner) => RfcDuration(inner)
				Err(error) => return Err(InvalidRfcDuration(error))
			}
			"rfc-period" => match RfcPeriod.parse(fields.payload) {
				Ok(inner) => RfcPeriod(inner)
				Err(error) => return Err(InvalidRfcPeriod(error))
			}
			"posix-boundary" => PosixBoundary(PosixBoundary.from_microseconds(integer(fields.payload)?))
			"posix-delta" => PosixDelta(PosixDelta.from_microseconds(integer(fields.payload)?))
			"posix-span" => PosixSpan(parse_span(fields.payload)?)
			"coverage" => Coverage(parse_coverage(fields.payload)?)
			_ => return Err(UnknownKind(fields.kind))
		}
		new(stored)
	}

	to_text : Persistence -> Str
	to_text = |wrapped| {
		{ kind, payload } = match wrapped.stored {
			EdtfDate(inner) => { kind: "edtf-date", payload: EdtfDate.to_text(inner) }
			OffsetTimestamp(inner) => { kind: "offset-timestamp", payload: OffsetTimestamp.to_text(inner) }
			ExactInterval(inner) => { kind: "exact-interval", payload: ExactInterval.to_text(inner) }
			Ixdtf(inner) => { kind: "ixdtf", payload: Ixdtf.to_text(inner) }
			RfcDateTime(inner) => { kind: "rfc-date-time", payload: RfcDateTime.to_text(inner) }
			RfcDuration(inner) => { kind: "rfc-duration", payload: RfcDuration.to_text(inner) }
			RfcPeriod(inner) => { kind: "rfc-period", payload: RfcPeriod.to_text(inner) }
			PosixBoundary(inner) => { kind: "posix-boundary", payload: PosixBoundary.to_microseconds(inner).to_str() }
			PosixDelta(inner) => { kind: "posix-delta", payload: PosixDelta.to_microseconds(inner).to_str() }
			PosixSpan(inner) => { kind: "posix-span", payload: span_text(inner) }
			Coverage(inner) => {
				var pieces = []
				for span in Coverage.to_spans(inner) {
					pieces = pieces.append(span_text(span))
				}
				{ kind: "coverage", payload: Str.join_with(pieces, ";") }
			}
		}
		description = match metadata(kind) {
			Some(inner) => inner
			None => crash "Every persistent Value has declared metadata"
		}
		# Coverage needs at most 43007 ASCII bytes without JSON escaping.
		# Text declarations need at most 4096 bytes; even six-byte escaping
		# plus fixed metadata fits inside the envelope's 64KiB cap.
		Json.to_str({ format: "roc-time", version: "1", kind, profile: description.profile, axis: description.axis, unit: description.unit, payload })
	}

	is_eq : Persistence, Persistence -> Bool
	is_eq = |a, b| a.stored == b.stored
	to_hash : Persistence, Hasher -> Hasher
	to_hash = |wrapped, hasher| match wrapped.stored {
		EdtfDate(inner) => inner.to_hash((0.U8).to_hash(hasher))
		OffsetTimestamp(inner) => inner.to_hash((1.U8).to_hash(hasher))
		ExactInterval(inner) => inner.to_hash((2.U8).to_hash(hasher))
		Ixdtf(inner) => inner.to_hash((3.U8).to_hash(hasher))
		RfcDateTime(inner) => inner.to_hash((4.U8).to_hash(hasher))
		RfcDuration(inner) => inner.to_hash((5.U8).to_hash(hasher))
		RfcPeriod(inner) => inner.to_hash((6.U8).to_hash(hasher))
		PosixBoundary(inner) => inner.to_hash((7.U8).to_hash(hasher))
		PosixDelta(inner) => inner.to_hash((8.U8).to_hash(hasher))
		PosixSpan(inner) => inner.to_hash((9.U8).to_hash(hasher))
		Coverage(inner) => inner.to_hash((10.U8).to_hash(hasher))
	}
	to_inspect : Persistence -> Str
	to_inspect = |wrapped| {
		kind = match wrapped.stored {
			EdtfDate(_) => "edtf-date"
			OffsetTimestamp(_) => "offset-timestamp"
			ExactInterval(_) => "exact-interval"
			Ixdtf(_) => "ixdtf"
			RfcDateTime(_) => "rfc-date-time"
			RfcDuration(_) => "rfc-duration"
			RfcPeriod(_) => "rfc-period"
			PosixBoundary(_) => "posix-boundary"
			PosixDelta(_) => "posix-delta"
			PosixSpan(_) => "posix-span"
			Coverage(_) => "coverage"
		}
		"Persistence(version=1, kind=${kind})"
	}
}

metadata = |kind| {
	profile = match kind {
		"edtf-date" => EdtfDate.profile
		"offset-timestamp" => OffsetTimestamp.profile
		"exact-interval" => ExactInterval.profile
		"ixdtf" => Ixdtf.profile
		"rfc-date-time" => RfcDateTime.profile
		"rfc-duration" => RfcDuration.profile
		"rfc-period" => RfcPeriod.profile
		"posix-boundary" => "posix-microseconds-v1"
		"posix-delta" => "posix-microseconds-v1"
		"posix-span" => "posix-half-open-span-v1"
		"coverage" => "posix-canonical-coverage-v1"
		_ => return None
	}
	core = kind == "posix-boundary" or kind == "posix-delta" or kind == "posix-span" or kind == "coverage"
	Some({
		profile,
		axis: if core {
			"posix-1970"
		} else {
			"none"
		},
		unit: if core {
			"microsecond"
		} else {
			"none"
		},
	})
}

# Canonical decimal strings avoid relying on JSON consumers' numeric range.
# Validate syntax before checked conversion so overflow is distinct from spelling.
integer : Str -> Try(I64, [InvalidInteger, OutOfRange, ..])
integer = |text| {
	bytes = text.to_utf8()
	if bytes.is_empty() {
		return Err(InvalidInteger)
	}
	negative = bytes.first() == Ok(45)
	start = if negative {
		1.U64
	} else {
		0
	}
	if bytes.len() == start {
		return Err(InvalidInteger)
	}
	first = match bytes.get(start) {
		Ok(value) => value
		Err(_) => crash "Nonempty decimal magnitude validated"
	}
	if first == 48 and (negative or bytes.len() > start + 1) {
		return Err(InvalidInteger)
	}
	for byte in bytes.drop_first(start) {
		if byte < 48 or byte > 57 {
			return Err(InvalidInteger)
		}
	}
	match I64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

span_text = |span| "${PosixBoundary.to_microseconds(PosixSpan.start(span)).to_str()}/${PosixBoundary.to_microseconds(PosixSpan.end(span)).to_str()}"

parse_span : Str -> Try(PosixSpan, [MalformedSpan, IncompleteSpan, InvalidInteger, OutOfRange, InvalidSpan([EmptySpan, ReversedBounds]), ..])
parse_span = |text| {
	var separators = 0.U8
	for byte in text.to_utf8() {
		if byte == 47 {
			separators = separators + 1
			if separators > 1 {
				return Err(MalformedSpan)
			}
		}
	}
	if separators == 0 {
		if !text.is_empty() and text != "-" {
			_ = integer(text)?
		}
		return Err(IncompleteSpan)
	}
	(start_text, end_text) = match text.split_on("/") {
		[start, end] => (start, end)
		_ => return Err(MalformedSpan)
	}
	if start_text.is_empty() {
		if !end_text.is_empty() {
			_ = integer(end_text)?
		}
		return Err(IncompleteSpan)
	}
	start = integer(start_text)?
	if end_text.is_empty() {
		return Err(IncompleteSpan)
	}
	end = integer(end_text)?
	match PosixSpan.new(PosixBoundary.from_microseconds(start), PosixBoundary.from_microseconds(end)) {
		Ok(span) => Ok(span)
		Err(error) => Err(InvalidSpan(error))
	}
}

parse_coverage : Str -> Try(Coverage, [TooManyMembers, MalformedSpan, IncompleteSpan, InvalidInteger, OutOfRange, InvalidSpan([EmptySpan, ReversedBounds]), NonCanonicalCoverage, ..])
parse_coverage = |text| {
	if text.is_empty() {
		return Ok(Coverage.empty)
	}
	var count = 1.U64
	# Count separators before allocating a member list or parsing any member.
	for byte in text.to_utf8() {
		if byte == 59 {
			count = count + 1
			if count > 1024 {
				return Err(TooManyMembers)
			}
		}
	}
	var members = []
	var previous_end = None
	for member_text in text.split_on(";") {
		span = parse_span(member_text)?
		match previous_end {
			None => {}
			Some(end) => if PosixSpan.start(span) <= end {
				return Err(NonCanonicalCoverage)
			}
		}
		previous_end = Some(PosixSpan.end(span))
		members = members.append(span)
	}
	match Coverage.from_sorted_spans(members) {
		Ok(coverage) => Ok(coverage)
		Err(_) => Err(NonCanonicalCoverage)
	}
}

expect {
	# Independent exact JSON fixture: these digits exceed IEEE754's exact
	# integer range and must remain quoted rather than pass through a float.
	text = "{\"format\":\"roc-time\",\"version\":\"1\",\"kind\":\"posix-boundary\",\"profile\":\"posix-microseconds-v1\",\"axis\":\"posix-1970\",\"unit\":\"microsecond\",\"payload\":\"9007199254740993\"}"
	value = Persistence.parse(text)?
	Persistence.value(value) == PosixBoundary(PosixBoundary.from_microseconds(9007199254740993)) and
		Persistence.parse(Persistence.to_text(value)) == Ok(value)
}
expect {
	var valid = Bool.True
	for number in [I64.lowest, -1, 0, 9007199254740993, I64.highest] {
		boundary = Persistence.new(PosixBoundary(PosixBoundary.from_microseconds(number)))?
		delta = Persistence.new(PosixDelta(PosixDelta.from_microseconds(number)))?
		valid = valid and boundary != delta and Persistence.parse(Persistence.to_text(boundary)) == Ok(boundary) and Persistence.parse(Persistence.to_text(delta)) == Ok(delta)
	}
	valid
}
expect {
	integer("9223372036854775808") == Err(OutOfRange) and integer("-9223372036854775809") == Err(OutOfRange) and
		integer("-0") == Err(InvalidInteger) and integer("00") == Err(InvalidInteger) and integer("+1") == Err(InvalidInteger) and
			integer("1e3") == Err(InvalidInteger) and integer("1.0") == Err(InvalidInteger) and integer(" 1") == Err(InvalidInteger)
}
expect {
	var valid = Bool.True
	for stored in [
		EdtfDate(EdtfDate.parse("1984?")?),
		OffsetTimestamp(OffsetTimestamp.parse("2000-01-01T00:00:00.120+00:00")?),
		ExactInterval(ExactInterval.parse("2000-01-01T00:00:00Z/2000-01-02T00:00:00Z")?),
		Ixdtf(Ixdtf.parse("2000-01-01T00:00:00Z[u-ca=hebrew][knort=blargel]")?),
		RfcDateTime(RfcDateTime.parse("20000101T000000")?),
		RfcDuration(RfcDuration.parse("P1DT1H")?),
		RfcPeriod(RfcPeriod.parse("20000101T000000/P1D")?),
	] {
		value = Persistence.new(stored)?
		valid = valid and Persistence.parse(Persistence.to_text(value)) == Ok(value)
	}
	valid
}
expect {
	base = { format: "roc-time", version: "1", kind: "edtf-date", profile: EdtfDate.profile, axis: "none", unit: "none", payload: "not a date" }
	test_parse({ ..base, format: "other" }) == Err(UnknownFormat("other")) and
		test_parse({ ..base, version: "2" }) == Err(UnknownVersion("2")) and
			test_parse({ ..base, kind: "ixdtf-snapshot" }) == Err(UnknownKind("ixdtf-snapshot")) and
				test_parse({ ..base, profile: "other" }) == Err(UnsupportedProfile("other")) and
					test_parse({ ..base, axis: "posix-1970" }) == Err(UnsupportedAxis("posix-1970")) and
						test_parse({ ..base, unit: "microsecond" }) == Err(UnsupportedUnit("microsecond")) and
							test_parse(base) == Err(InvalidEdtfDate(Malformed))
}

test_parse = |fields| {
	envelope = match PersistenceEnvelope.new(fields) {
		Ok(value) => value
		Err(_) => crash "Small metadata fixture fits envelope"
	}
	Persistence.parse(PersistenceEnvelope.to_text(envelope))
}

expect {
	boundary = Persistence.new(PosixBoundary(PosixBoundary.from_microseconds(1)))?
	replay = Persistence.parse(Persistence.to_text(boundary))?
	delta = Persistence.new(PosixDelta(PosixDelta.from_microseconds(1)))?
	dictionary = Dict.insert(Dict.insert(Dict.empty(), boundary, "position"), delta, "displacement")
	Dict.get(dictionary, replay) == Ok("position") and Dict.get(dictionary, delta) == Ok("displacement") and
		Str.inspect(boundary) == "Persistence(version=1, kind=posix-boundary)"
}

expect {
	# Extent exists even when its signed I64 coordinate width cannot fit.
	wide = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
	stored = Persistence.new(PosixSpan(wide))?
	base = { format: "roc-time", version: "1", kind: "posix-span", profile: "posix-half-open-span-v1", axis: "posix-1970", unit: "microsecond", payload: "-9223372036854775808/9223372036854775807" }
	PosixSpan.coordinate_width(wide) == Err(OutOfRange) and test_parse(base) == Ok(stored) and Persistence.parse(Persistence.to_text(stored)) == Ok(stored)
}
expect {
	first = PosixSpan.new(PosixBoundary.from_microseconds(-2), PosixBoundary.from_microseconds(0))?
	second = PosixSpan.new(PosixBoundary.from_microseconds(1), PosixBoundary.from_microseconds(3))?
	coverage = Coverage.from_spans([second, first])
	stored = Persistence.new(Coverage(coverage))?
	empty = Persistence.new(Coverage(Coverage.empty))?
	base = { format: "roc-time", version: "1", kind: "coverage", profile: "posix-canonical-coverage-v1", axis: "posix-1970", unit: "microsecond", payload: "-2/0;1/3" }
	test_parse(base) == Ok(stored) and test_parse({ ..base, payload: "" }) == Ok(empty) and
		Persistence.parse(Persistence.to_text(stored)) == Ok(stored) and Persistence.parse(Persistence.to_text(empty)) == Ok(empty)
}
expect {
	parse_span("0/0") == Err(InvalidSpan(EmptySpan)) and parse_span("1/0") == Err(InvalidSpan(ReversedBounds)) and
		parse_span("0") == Err(IncompleteSpan) and parse_span("0/") == Err(IncompleteSpan) and parse_span("/1") == Err(IncompleteSpan) and
			parse_span("0/1/2") == Err(MalformedSpan) and parse_span("00/1") == Err(InvalidInteger) and
				parse_span("0/9223372036854775808") == Err(OutOfRange) and
					parse_coverage("0/1;") == Err(IncompleteSpan) and
						parse_coverage("1/2;0/1") == Err(NonCanonicalCoverage) and parse_coverage("0/2;1/3") == Err(NonCanonicalCoverage) and
							parse_coverage("0/1;1/2") == Err(NonCanonicalCoverage) and parse_coverage("0/1;0/1") == Err(NonCanonicalCoverage)
}
expect {
	var spans = []
	var index = 0.I64
	while index < 1025 {
		span = PosixSpan.new(PosixBoundary.from_microseconds(index * 2), PosixBoundary.from_microseconds(index * 2 + 1))?
		spans = spans.append(span)
		index = index + 1
	}
	large = Coverage.from_spans(spans)
	limit = Coverage.from_spans(spans.drop_last(1))
	accepted = Persistence.new(Coverage(limit))?
	Persistence.new(Coverage(large)) == Err(TooManyMembers) and Persistence.parse(Persistence.to_text(accepted)) == Ok(accepted) and
		parse_coverage(Str.join_with(List.repeat("0/1", 1025), ";")) == Err(TooManyMembers)
}
