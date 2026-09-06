import fuzz.Fuzz
import time.ResolvedBoundary
import time.ResolvedSelection
import time.Coverage
import time.Persistence
import time.Explanation
import time.SemanticFact
import time.RfcDateTime
import time.RfcDuration
import time.RfcPeriod
import time.PosixDelta
import time.EdtfDate
import time.OffsetTimestamp
import time.CalendarValue
import time.QualifiedCalendarValue
import time.CalendarDate
import time.LocalDateTime
import time.ClockTime
import time.FixedOffset
import time.GregorianDate
import time.PosixSpan
import time.ZoneRules
import time.ExactInterval
import time.Ixdtf
import time.PosixBoundary

# R02/R13/R14: generated valid Gregorian dates in 1900..2100, supplied EDTF
# year/month/day resolution and whole qualifiers; complete offset timestamps
# with 0..6 fractional digits. The date oracle counts whole years/months using
# the Gregorian divisibility law, independently of CalendarDate conversions.
InterchangeCase := { year : U16, month : U8, day : U8, precision : U8, qualifier : U8, seconds : U32, fraction : U32, digits : U8, offset : I16 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(InterchangeCase)
	generator_for = |_| { year: Fuzz.map(Fuzz.u64_in(1900, 2100), |n| n.to_u16_wrap()), month: Fuzz.u8_in(1, 12), day: Fuzz.u8_in(0, 30), precision: Fuzz.u8_in(0, 2), qualifier: Fuzz.u8_in(0, 3), seconds: Fuzz.map(Fuzz.u64_in(0, 86399), |n| n.to_u32_wrap()), fraction: Fuzz.map(Fuzz.u64_in(0, 999999), |n| n.to_u32_wrap()), digits: Fuzz.u8_in(0, 6), offset: Fuzz.map(Fuzz.u64_in(0, 2878), |n| (n.to_i64_wrap() - 1439).to_i16_wrap()) }.Fuzz
	check : InterchangeCase -> Fuzz.Outcome
	check = |input| {
		day = 1 + input.day % month_days(input.year, input.month)
		date_text = "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}-${pad(day.to_u64(), 2)}"
		check_edtf(input, day, date_text)
		check_timestamp(input, day, date_text)
		check_timestamp_format_limits(input)
		check_malformed(input, date_text)
		Fuzz.Outcome.Keep
	}
}

month_days = |year, month| if month == 2 {
	if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) {
		29.U8
	} else {
		28
	}
} else if [4.U8, 6, 9, 11].contains(month) {
	30
} else {
	31
}

pad = |number, width| {
	raw = number.to_str()
	var result = raw
	while result.count_utf8_bytes() < width {
		result = "0${result}"
	}
	result
}

check_edtf = |input, day, date_text| {
	base = match input.precision {
		0 => input.year.to_str()
		1 => "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}"
		_ => date_text
	}
	suffix = match input.qualifier {
		0 => ""
		1 => "?"
		2 => "~"
		_ => "%"
	}
	source = "${base}${suffix}"
	parsed = match EdtfDate.parse(source) {
		Ok(value) => value
		Err(_) => crash "Generated valid EDTF date rejected"
	}
	check_persistence(EdtfDate(parsed), { kind: "edtf-date", profile: "edtf-gregorian-date-v1", payload: source, axis: "none", unit: "none" })
	if EdtfDate.to_text(parsed) != source or EdtfDate.parse(EdtfDate.to_text(parsed)) != Ok(parsed) {
		crash "EDTF canonical serialization changed supplied resolution or qualifier"
	}
	description = EdtfDate.description(parsed)
	value = QualifiedCalendarValue.described_value(description)
	expected_resolution = match input.precision {
		0 => Year
		1 => Month
		_ => Day
	}
	fields = CalendarDate.to_fields(LocalDateTime.date(CalendarValue.start_label(value)))
	if CalendarValue.resolution(value) != expected_resolution or fields.year != input.year.to_i64() or
		fields.month != (
			if input.precision == 0 {
				1
			} else {
				input.month
			}
		) or
			fields.day != (
				if input.precision < 2 {
					1
				} else {
					day
				}
			) {
		crash "EDTF parsed fields differ from generated calendar description"
	}
	expected_qualifications = match input.qualifier {
		0 => []
		1 => [{ scope: Whole, qualifier: Uncertain }]
		2 => [{ scope: Whole, qualifier: Approximate }]
		_ => [{ scope: Whole, qualifier: UncertainApproximate }]
	}
	if QualifiedCalendarValue.qualifications(description) != expected_qualifications or EdtfDate.from_description(description) != Ok(parsed) {
		crash "EDTF native adapter lost qualifier facts"
	}
}

check_timestamp = |input, day, date_text| {
	var scale = 1.U32
	var count = 0.U8
	while count < input.digits {
		scale = scale * 10
		count = count + 1
	}
	fraction = input.fraction % scale
	fraction_text = if input.digits == 0 {
		""
	} else {
		".${pad(fraction.to_u64(), input.digits.to_u64())}"
	}
	h = input.seconds // 3600
	m = (input.seconds // 60) % 60
	s = input.seconds % 60
	clock_text = "${pad(h.to_u64(), 2)}:${pad(m.to_u64(), 2)}:${pad(s.to_u64(), 2)}${fraction_text}"
	magnitude = if input.offset < 0 {
		-input.offset
	} else {
		input.offset
	}
	sign = if input.offset < 0 {
		"-"
	} else {
		"+"
	}
	numeric = "${sign}${pad((magnitude // 60).to_u64_wrap(), 2)}:${pad((magnitude % 60).to_u64_wrap(), 2)}"
	# Alternate asserted offsets and the two UTC spellings. -00:00 records
	# unknown local offset like Z; +00:00 retains an asserted zero offset.
	unasserted = input.qualifier < 2
	suffix = if unasserted {
		if input.qualifier == 0 {
			"Z"
		} else {
			"-00:00"
		}
	} else {
		numeric
	}
	source = "${date_text}T${clock_text}${suffix}"
	canonical = "${date_text}T${clock_text}${
		if unasserted {
			"Z"
		} else {
			numeric
		}
	}"
	parsed = match OffsetTimestamp.parse(source) {
		Ok(value) => value
		Err(_) => crash "Generated valid offset timestamp rejected"
	}
	check_persistence(OffsetTimestamp(parsed), { kind: "offset-timestamp", profile: "rfc3339-microseconds-rfc9557-base-v1", payload: canonical, axis: "none", unit: "none" })
	if OffsetTimestamp.to_text(parsed) != canonical or OffsetTimestamp.parse(canonical) != Ok(parsed) {
		crash "Timestamp canonical serialization changed semantic parts"
	}
	parts = OffsetTimestamp.parts(parsed)
	expected_offset = if unasserted {
		UnassertedUtc
	} else {
		Asserted(FixedOffset.from_seconds(input.offset.to_i32() * 60))
	}
	fields = GregorianDate.to_fields(parts.date)
	clock = ClockTime.to_fields(parts.clock)
	micros = fraction * (1000000 // scale)
	if fields != { year: input.year.to_i64(), month: input.month, day } or
		clock != { hour: h.to_u8_wrap(), minute: m.to_u8_wrap(), second: s.to_u8_wrap(), microsecond: micros } or
			parts.fraction_digits != input.digits or parts.offset != expected_offset or OffsetTimestamp.new(parts) != Ok(parsed) {
		crash "Timestamp fields differ from generated input"
	}
	var days = 0.I64
	var year = 1900.U16
	while year < input.year {
		days = days + (
			if month_days(year, 2) == 29 {
				366
			} else {
				365
			}
		)
		year = year + 1
	}
	var month = 1.U8
	while month < input.month {
		days = days + month_days(input.year, month).to_i64()
		month = month + 1
	}
	# 1900-01-01 is 25567 whole days before the POSIX epoch (70 ordinary
	# years plus 17 leap days); all arithmetic stays within this bounded domain.
	elapsed_days = days + day.to_i64() - 1 - 25567
	offset_seconds = if unasserted {
		0.I64
	} else {
		input.offset.to_i64() * 60
	}
	expected = (elapsed_days * 86400 + input.seconds.to_i64() - offset_seconds) * 1000000 + micros.to_i64()
	if OffsetTimestamp.boundary(parsed) != Ok(PosixBoundary.from_microseconds(expected)) or
		OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(expected), expected_offset, input.digits) != Ok(parsed) {
		crash "Timestamp boundary differs from independent Gregorian day count"
	}
	check_exact_interval(input, date_text, parsed, expected, elapsed_days)
	check_ixdtf(input, parsed, expected)
	check_core_persistence(expected)
	check_rfc_persistence(input, day, h, m, s)
}

# Mutations remain in the property's domain: ordinary structured public failures
# must be observed rather than discarded by the harness.
check_malformed = |input, date_text| {
	# Every fixed-field position is independently damaged, and every valid
	# fixed-field prefix remains incomplete. Observe shared/sliced ASCII input.
	bytes = "${date_text}T12:34:56Z".to_utf8()
	var position = 0.U64
	while position < 19 {
		prefix = bytes.sublist({ start: 0, len: position })
		suffix = bytes.sublist({ start: position + 1, len: bytes.len() - position - 1 })
		if OffsetTimestamp.parse(ascii_text(prefix)) != Err(Incomplete) or
			OffsetTimestamp.parse(ascii_text(prefix.append(64).concat(suffix))) != Err(Malformed) {
			crash "Timestamp fixed-field mutation or prefix misclassified"
		}
		position = position + 1
	}
	invalid_day = month_days(input.year, input.month) + 1
	invalid_date = "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}-${pad(invalid_day.to_u64(), 2)}"
	if EdtfDate.parse(invalid_date) != Err(Malformed) or EdtfDate.parse("${input.year.to_str()}-") != Err(Incomplete) {
		crash "EDTF invalid date or incomplete prefix misclassified"
	}
	if OffsetTimestamp.parse("${invalid_date}T00:00:00Z") != Err(InvalidDate) or
		OffsetTimestamp.parse("${date_text}T00:00:00+24:00") != Err(InvalidOffset) or
			OffsetTimestamp.parse("${date_text}T00:00:00.0000000Z") != Err(UnsupportedPrecision) or
				OffsetTimestamp.parse("${date_text}T23:59:60Z") != Err(UnsupportedLeapSecond) {
		crash "Timestamp malformed fields or unsupported precision misclassified"
	}
	# Mixed faults pin public error precedence rather than merely rejecting.
	if OffsetTimestamp.parse("${input.year.to_str()}-99-01T00:00:0@Z") != Err(Malformed) or
		OffsetTimestamp.parse("${invalid_date}T24:00:00Z") != Err(InvalidTime) or
			OffsetTimestamp.parse("${date_text}T00:00:00+24") != Err(InvalidOffset) or
				OffsetTimestamp.parse("${date_text}T00:00:00.0000000+0x") != Err(Malformed) or
					OffsetTimestamp.parse("${date_text}T00:00:00.0000000Z[UTC]") != Err(UnsupportedAnnotations) or
						OffsetTimestamp.parse("${date_text}T23:59:60") != Err(UnsupportedLeapSecond) {
		crash "Timestamp mixed-fault precedence changed"
	}
}

ascii_text = |bytes| match Str.from_utf8(bytes) {
	Ok(text) => text
	Err(_) => crash "ASCII mutation fixture invariant"
}

# R01/R08/R14: exact interval extent is independently calculated in integer
# microseconds. Endpoints deliberately use different offsets; textual/local
# ordering must never replace ordering of resolved boundaries.
check_exact_interval = |input, date_text, timestamp, expected, elapsed_days| {
	# A whole second preserves every generated decimal precision exactly.
	end = match OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(expected + 1000000), UnassertedUtc, input.digits) {
		Ok(value) => value
		Err(_) => crash "In-range generated interval end rejected"
	}
	source = "${OffsetTimestamp.to_text(timestamp)}/${OffsetTimestamp.to_text(end)}"
	interval = match ExactInterval.parse(source) {
		Ok(value) => value
		Err(_) => crash "Valid generated exact interval rejected"
	}
	check_persistence(ExactInterval(interval), { kind: "exact-interval", profile: "exact-offset-interval-v1", payload: source, axis: "none", unit: "none" })
	expected_span = model_span(expected, expected + 1000000)
	check_exact_explanation(interval, expected_span, input.digits, timestamp, end)
	if ExactInterval.span(interval) != expected_span or ExactInterval.to_text(interval) != source or
		ExactInterval.parse(ExactInterval.to_text(interval)) != Ok(interval) or ExactInterval.new(timestamp, end) != Ok(interval) {
		crash "Exact interval differs from independent endpoint extent"
	}
	converted = match ExactInterval.from_span(expected_span, UnassertedUtc, input.digits) {
		Ok(value) => value
		Err(_) => crash "Aligned exact span serialization rejected"
	}
	reparsed = match ExactInterval.parse(ExactInterval.to_text(converted)) {
		Ok(value) => value
		Err(_) => crash "Formatted exact span did not reparse"
	}
	if ExactInterval.span(reparsed) != expected_span {
		crash "Exact interval span round trip changed extent"
	}
	reverse_labels = "${date_text}T10:00:00+02:00/${date_text}T09:00:00Z"
	small = match ExactInterval.parse(reverse_labels) {
		Ok(value) => value
		Err(_) => crash "Resolved interval order confused with local endpoint order"
	}
	midnight = elapsed_days * 86400000000
	if ExactInterval.span(small) != model_span(midnight + 28800000000, midnight + 32400000000) {
		crash "Different-offset interval differs from independent hour model"
	}
	if ExactInterval.parse("${date_text}T09:00:00Z/${date_text}T10:00:00+02:00") != Err(ReversedBounds) or
		ExactInterval.new(timestamp, timestamp) != Err(EmptySpan) {
		crash "Exact interval invalid endpoint order was accepted"
	}
}

model_span = |start, end| match PosixSpan.new(PosixBoundary.from_microseconds(start), PosixBoundary.from_microseconds(end)) {
	Ok(value) => value
	Err(_) => crash "Ordered independent oracle span"
}

# RFC9557 sections2,3.3–3.4,5: generated model extensions of the sourced UTC
# versus asserted-offset examples. Immutable synthetic constant rules make the
# expected offset and local coordinate explicit; no host zone database is used.
check_ixdtf = |input, timestamp, expected| {
	base = OffsetTimestamp.to_text(timestamp)
	critical = input.precision == 0
	marker = if critical {
		"!"
	} else {
		""
	}
	source = "${base}[${marker}Synthetic/Interchange][u-ca=gregory][u-ca=hebrew][knort=v${input.digits.to_str()}]"
	parsed = match Ixdtf.parse(source) {
		Ok(value) => value
		Err(_) => crash "Generated supported IXDTF annotations rejected"
	}
	check_persistence(Ixdtf(parsed), { kind: "ixdtf", profile: "rfc9557-microseconds-v1", payload: source, axis: "none", unit: "none" })
	if Ixdtf.to_text(parsed) != source or Ixdtf.parse(Ixdtf.to_text(parsed)) != Ok(parsed) or
		Ixdtf.parts(parsed).timestamp != timestamp or Ixdtf.preferred_calendar(parsed) != Some("gregory") or
			Ixdtf.new(Ixdtf.parts(parsed)) != Ok(parsed) {
		crash "IXDTF annotation order, base resolution, or declaration changed"
	}
	tags = Ixdtf.parts(parsed).tags
	if tags != [{ critical: Bool.False, key: "u-ca", value: "gregory" }, { critical: Bool.False, key: "u-ca", value: "hebrew" }, { critical: Bool.False, key: "knort", value: "v${input.digits.to_str()}" }] {
		crash "IXDTF elective duplicate tags were not retained"
	}
	offset = input.offset.to_i32() * 60
	rules = constant_rules(expected, offset, "v1")
	snapshot = match Ixdtf.resolve(parsed, Some(rules)) {
		Ok(value) => value
		Err(_) => crash "Matching generated IXDTF interpretation failed"
	}
	if Ixdtf.Snapshot.boundary(snapshot) != PosixBoundary.from_microseconds(expected) or
		Ixdtf.Snapshot.source(snapshot) != parsed or Ixdtf.Snapshot.offset(snapshot) != FixedOffset.from_seconds(offset) {
		crash "IXDTF snapshot changed source position or rule offset"
	}
	_ = check_snapshot_persistence(snapshot, expected, offset)
	check_transition_snapshot_persistence(expected)
	check_civil_snapshot_persistence(expected)
	check_snapshot_explanation(snapshot, expected, Gregorian, input.precision.to_u64())
	presentation = match Ixdtf.Snapshot.presentation(snapshot) {
		Ok(value) => value
		Err(_) => crash "First elective Gregorian calendar did not win"
	}
	if FixedOffset.resolve(FixedOffset.from_seconds(0), presentation) != Ok(PosixBoundary.from_microseconds(expected + offset.to_i64() * 1000000)) {
		crash "IXDTF presentation differs from independent constant-offset model"
	}
	match Ixdtf.resolve(parsed, None) {
		Err(NeedsContext) => {}
		_ => crash "Named zone accepted without explicit rules"
	}
	changed_rules = constant_rules(expected, offset + 60, "v2")
	if input.qualifier < 2 {
		changed = match Ixdtf.Snapshot.reresolve(snapshot, Some(changed_rules)) {
			Ok(value) => value
			Err(_) => crash "Unasserted UTC rejected changed local rules"
		}
		if Ixdtf.Snapshot.boundary(changed) != PosixBoundary.from_microseconds(expected) or
			Ixdtf.Snapshot.offset(changed) != FixedOffset.from_seconds(offset + 60) or
				Ixdtf.Snapshot.offset(snapshot) != FixedOffset.from_seconds(offset) or
					Ixdtf.Snapshot.presentation(snapshot) != Ok(presentation) {
			crash "IXDTF changed rules mutated retained snapshot or UTC position"
		}
	} else {
		match Ixdtf.Snapshot.reresolve(snapshot, Some(changed_rules)) {
			Err(OffsetConflict) => {}
			_ => crash "Asserted numeric offset ignored rule conflict"
		}
	}
	# An elective unsupported calendar changes only presentation availability.
	hebrew = match Ixdtf.parse("${base}[u-ca=hebrew]") {
		Ok(value) => value
		Err(_) => crash "Elective calendar preference rejected"
	}
	hebrew_snapshot = match Ixdtf.resolve(hebrew, None) {
		Ok(value) => value
		Err(_) => crash "Elective calendar reinterpreted Gregorian timestamp"
	}
	if Ixdtf.Snapshot.boundary(hebrew_snapshot) != PosixBoundary.from_microseconds(expected) or
		Ixdtf.Snapshot.presentation(hebrew_snapshot) != Err(UnsupportedCalendar("hebrew")) {
		crash "Calendar presentation preference changed timestamp meaning"
	}
	_ = check_snapshot_persistence(
		hebrew_snapshot,
		expected,
		if input.qualifier < 2 {
			0
		} else {
			offset
		},
	)
	check_snapshot_explanation(hebrew_snapshot, expected, UnsupportedCalendar("hebrew"), input.precision.to_u64())
	if Ixdtf.parse("${base}[!knort=v${input.digits.to_str()}]") != Err(UnknownCritical) or
		Ixdtf.parse("${base}[!u-ca=gregory][u-ca=hebrew]") != Err(ConflictingCritical) {
		crash "Critical annotation errors were ignored"
	}
}

constant_rules = |boundary, offset, version| match ZoneRules.new_bounded("Synthetic/Interchange", version, model_span(boundary - 172800000000, boundary + 172800000000), FixedOffset.from_seconds(offset), [], { minimum: offset, maximum: offset }) {
	Ok(value) => value
	Err(_) => crash "Valid fixed synthetic interpretation context"
}

# R01/R14: versioned envelopes preserve nominal kind and exact string payloads.
# Expected metadata is declared here independently of the serializer. The
# underlying temporal fields/boundaries are checked against the models above;
# this law adds persistence without using a round trip as the semantic oracle.
check_persistence = |value, expected| {
	envelope = match Persistence.new(value) {
		Ok(found) => found
		Err(_) => crash "Bounded persistence declaration rejected"
	}
	text = Persistence.to_text(envelope)
	fields : Try({ format : Str, version : Str, kind : Str, profile : Str, axis : Str, unit : Str, payload : Str }, [InvalidJson(Str), MissingRequiredField(Str)])
	fields = Json.parse(text)
	match fields {
		Ok(record) => if record != { format: "roc-time", version: "1", kind: expected.kind, profile: expected.profile, axis: expected.axis, unit: expected.unit, payload: expected.payload } {
			crash "Persistence envelope changed independently expected metadata or payload"
		}
		Err(_) => crash "Persistence envelope is not a JSON object of seven strings"
	}
	replay = match Persistence.parse(text) {
		Ok(found) => found
		Err(_) => crash "Canonical persistence envelope rejected"
	}
	if Persistence.value(replay) != value or Persistence.to_text(replay) != text {
		crash "Persistence round trip lost nominal value or canonical text"
	}
}

check_core_persistence = |generated| {
	check_persistence(PosixSpan(model_span(I64.lowest, I64.highest)), { kind: "posix-span", profile: "posix-half-open-span-v1", axis: "posix-1970", unit: "microsecond", payload: "-9223372036854775808/9223372036854775807" })
	# These values cannot all be represented exactly by a JSON/F64 number.
	# Keep them as decimal strings and verify both coordinate domain tags.
	for coordinate in [I64.lowest, -9007199254740993, 0, 9007199254740993, I64.highest, generated] {
		payload = coordinate.to_str()
		check_persistence(PosixBoundary(PosixBoundary.from_microseconds(coordinate)), { kind: "posix-boundary", profile: "posix-microseconds-v1", axis: "posix-1970", unit: "microsecond", payload })
		check_persistence(PosixDelta(PosixDelta.from_microseconds(coordinate)), { kind: "posix-delta", profile: "posix-microseconds-v1", axis: "posix-1970", unit: "microsecond", payload })
	}
	bad_version = Json.to_str({ format: "roc-time", version: "2", kind: "posix-boundary", profile: "posix-microseconds-v1", axis: "posix-1970", unit: "microsecond", payload: generated.to_str() })
	match Persistence.parse(bad_version) {
		Err(UnknownVersion("2")) => {}
		_ => crash "Unknown persistence version accepted"
	}
	bad_unit = Json.to_str({ format: "roc-time", version: "1", kind: "posix-boundary", profile: "posix-microseconds-v1", axis: "posix-1970", unit: "nanosecond", payload: generated.to_str() })
	match Persistence.parse(bad_unit) {
		Err(UnsupportedUnit("nanosecond")) => {}
		_ => crash "Persistence silently changed coordinate units"
	}
}

check_rfc_persistence = |input, day, h, m, s| {
	source = "${input.year.to_str()}${pad(input.month.to_u64(), 2)}${pad(day.to_u64(), 2)}T${pad(h.to_u64(), 2)}${pad(m.to_u64(), 2)}${pad(s.to_u64(), 2)}Z"
	date = match RfcDateTime.parse(source) {
		Ok(found) => found
		Err(_) => crash "Generated supported RFC datetime rejected"
	}
	duration_source = "PT${(input.seconds + 1).to_str()}S"
	duration = match RfcDuration.parse(duration_source) {
		Ok(found) => found
		Err(_) => crash "Generated positive RFC duration rejected"
	}
	period_source = "${source}/${duration_source}"
	period = match RfcPeriod.parse(period_source) {
		Ok(found) => found
		Err(_) => crash "Generated supported RFC period rejected"
	}
	check_persistence(RfcDateTime(date), { kind: "rfc-date-time", profile: "rfc5545-datetime-values-v1", axis: "none", unit: "none", payload: source })
	check_persistence(RfcDuration(duration), { kind: "rfc-duration", profile: "rfc5545-positive-duration-v1", axis: "none", unit: "none", payload: duration_source })
	check_persistence(RfcPeriod(period), { kind: "rfc-period", profile: "rfc5545-period-values-v1", axis: "none", unit: "none", payload: period_source })
	check_rfc_explanation(input, day, h, m, s, source, date, duration, period)
}

# R09/R12/R14: independent date-count oracle supplies the expected position.
# Unsupported presentation and resolved position coexist; rendering completeness
# is a separate result and cannot erase either typed semantic fact.
check_snapshot_explanation = |snapshot, expected, presentation, budget| {
	source = Explanation.new(Snapshot(snapshot))
	match Explanation.fact_at(source, 0) {
		Item(fact) => match SemanticFact.kind(fact) {
			ResolvedPosition(data) => if data.boundary != PosixBoundary.from_microseconds(expected) {
				crash "Explanation changed independently modeled snapshot position"
			}
			_ => crash "Snapshot explanation omitted its stored position"
		}
		End => crash "Snapshot explanation is unexpectedly empty"
	}
	match Explanation.fact_at(source, 1) {
		Item(fact) => if SemanticFact.kind(fact) != Presentation(presentation) {
			crash "Snapshot explanation erased preferred-calendar status"
		}
		End => crash "Snapshot explanation omitted presentation status"
	}
	var index = 0.U64
	while index < Explanation.fact_count(source) {
		match Explanation.fact_at(source, index) {
			Item(fact) => if SemanticFact.kind(fact) == Requirement(ZoneContext) {
				crash "Bound snapshot was described as needing zone context again"
			}
			End => crash "Declared fact count exceeds available snapshot facts"
		}
		index = index + 1
	}
	full = Explanation.plain(source, { max_facts: 64, max_utf8_bytes: 16384 })
	prefix = Explanation.plain(source, { max_facts: budget, max_utf8_bytes: 16384 })
	tiny = Explanation.plain(source, { max_facts: 64, max_utf8_bytes: budget * 17 })
	if full.status != Complete or full.visited_facts != Explanation.fact_count(source) or
		prefix.status != Limited(FactLimit) or prefix.visited_facts > budget or
			tiny.text.count_utf8_bytes() > budget * 17 or tiny.status != Limited(ByteLimit) {
		crash "Snapshot explanation did not respect independent fact/output limits"
	}
}

# Facts preserve declaration distinctions independently of renderer wording.
# The exact span oracle is the integer endpoint model above; RFC expectations
# come from generated fields and separately declared calendar/coordinate units.
explanation_fact = |source, index| match Explanation.fact_at(source, index) {
	Item(fact) => SemanticFact.kind(fact)
	End => crash "Expected declaration fact is absent"
}

check_exact_explanation = |interval, expected_span, digits, start, end| {
	source = Explanation.new(ExactInterval(interval))
	if explanation_fact(source, 0) != ExactIntervalDescription({ span: expected_span }) {
		crash "Exact interval explanation changed independently modeled extent"
	}
	for entry in [{ index: 1.U64, role: Start, endpoint: start }, { index: 2.U64, role: End, endpoint: end }] {
		match explanation_fact(source, entry.index) {
			OffsetEndpoint(data) => if data.role != entry.role or data.fraction_digits != digits or data.local != OffsetTimestamp.local_label(entry.endpoint) or data.offset != OffsetTimestamp.parts(entry.endpoint).offset {
				crash "Interval explanation lost endpoint role or supplied width"
			}
			_ => crash "Interval explanation omitted an endpoint assertion"
		}
	}
	check_declaration_limits(source, digits.to_u64())
}

check_rfc_explanation = |input, day, h, m, s, utc_source, date, duration, period| {
	local_text = match utc_source.drop_last_bytes(1) {
		Ok(value) => value
		Err(_) => crash "Generated RFC text has an ASCII UTC suffix"
	}
	local = match RfcDateTime.parse(local_text) {
		Ok(value) => value
		Err(_) => crash "Generated local RFC label rejected"
	}
	for entry in [{ value: date, form: Utc }, { value: local, form: Local }] {
		source = Explanation.new(RfcDateTime(entry.value))
		match explanation_fact(source, 0) {
			RfcDateTimeDescription(data) => {
				if data.role != Standalone or data.form != entry.form or
					CalendarDate.to_fields(LocalDateTime.date(data.local)) != { year: input.year.to_i64(), month: input.month, day } or
						ClockTime.to_fields(LocalDateTime.clock(data.local)) != { hour: h.to_u8_wrap(), minute: m.to_u8_wrap(), second: s.to_u8_wrap(), microsecond: 0 } {
					crash "RFC explanation changed supplied fields or local/UTC form"
				}
			}
			_ => crash "RFC datetime description fact absent"
		}
		if entry.form == Local and explanation_fact(source, 1) != Requirement(ZoneContext) {
			crash "Local RFC label was explained without required context"
		}
		check_declaration_limits(source, input.digits.to_u64())
	}
	seconds = input.seconds.to_i64() + 1
	coordinate = Explanation.new(RfcDuration(duration))
	if explanation_fact(coordinate, 0) != RfcDurationDescription({ role: Standalone, days: 0, seconds }) {
		crash "RFC coordinate duration was reinterpreted as calendar days"
	}
	days = input.precision.to_i64() + 1
	calendar_duration = match RfcDuration.parse("P${days.to_str()}D") {
		Ok(value) => value
		Err(_) => crash "Generated positive calendar-day duration rejected"
	}
	calendar = Explanation.new(RfcDuration(calendar_duration))
	if explanation_fact(calendar, 0) != RfcDurationDescription({ role: Standalone, days, seconds: 0 }) {
		crash "RFC calendar duration was converted into fixed coordinate seconds"
	}
	for source in [coordinate, calendar, Explanation.new(RfcPeriod(period))] {
		check_declaration_limits(source, input.digits.to_u64())
	}
	period_source = Explanation.new(RfcPeriod(period))
	if explanation_fact(period_source, 2) != RfcDurationDescription({ role: PeriodEnding, days: 0, seconds }) {
		crash "RFC period duration lost its supplied anchor role"
	}
	local_period = match RfcPeriod.parse("${local_text}/P${days.to_str()}D") {
		Ok(value) => value
		Err(_) => crash "Generated local RFC period rejected"
	}
	local_period_source = Explanation.new(RfcPeriod(local_period))
	if explanation_fact(local_period_source, 3) != Requirement(ZoneContext) or
		explanation_fact(local_period_source, 2) != RfcDurationDescription({ role: PeriodEnding, days, seconds: 0 }) {
		crash "Local period explanation invented an interpreted endpoint"
	}
	check_declaration_limits(local_period_source, input.digits.to_u64())
}

check_declaration_limits = |source, bytes| {
	full = Explanation.plain(source, { max_facts: 16, max_utf8_bytes: 8192 })
	zero = Explanation.plain(source, { max_facts: 0, max_utf8_bytes: 8192 })
	tiny = Explanation.plain(source, { max_facts: 16, max_utf8_bytes: bytes })
	if full.status != Complete or full.visited_facts != Explanation.fact_count(source) or
		zero.status != Limited(FactLimit) or zero.visited_facts != 0 or !zero.text.is_empty() or
			tiny.status != Limited(ByteLimit) or tiny.text.count_utf8_bytes() > bytes {
		crash "Declaration explanation ignored finite rendering limits"
	}
	match Explanation.fact_at(source, U64.highest) {
		End => {}
		_ => crash "Large fact index overflowed or fabricated a declaration fact"
	}
}

# R09/R14: persistence restores an actual immutable interpretation, not just
# name/version labels or its current point result. Expected positions and
# offsets are supplied by the independent models above and below.
check_snapshot_persistence = |snapshot, expected, expected_offset| {
	wrapped = match Persistence.new(IxdtfSnapshot(snapshot)) {
		Ok(value) => value
		Err(_) => crash "Bounded snapshot persistence rejected"
	}
	text = Persistence.to_text(wrapped)
	restored_envelope = match Persistence.parse(text) {
		Ok(value) => value
		Err(_) => crash "Snapshot canonical persistence failed to restore"
	}
	restored = match Persistence.value(restored_envelope) {
		IxdtfSnapshot(value) => value
		_ => crash "Persistence changed snapshot kind"
	}
	if Ixdtf.Snapshot.boundary(restored) != PosixBoundary.from_microseconds(expected) or
		Ixdtf.Snapshot.offset(restored) != FixedOffset.from_seconds(expected_offset) or
			Ixdtf.Snapshot.source(restored) != Ixdtf.Snapshot.source(snapshot) or
				Ixdtf.Snapshot.presentation(restored) != Ixdtf.Snapshot.presentation(snapshot) or
					restored != snapshot or Persistence.to_text(restored_envelope) != text {
		crash "Persisted snapshot lost source, modeled result or semantic identity"
	}
	match (Ixdtf.Snapshot.context(snapshot), Ixdtf.Snapshot.context(restored)) {
		(None, None) => {}
		(Some(original), Some(replay)) => if ZoneRules.definition(original) != ZoneRules.definition(replay) {
			crash "Snapshot persistence changed full immutable interpretation data"
		}
		_ => crash "Snapshot context presence changed"
	}
	restored
}

check_transition_snapshot_persistence = |coordinate| {
	timestamp = match OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(coordinate), UnassertedUtc, 6) {
		Ok(value) => value
		Err(_) => crash "Bounded model UTC timestamp rejected"
	}
	source = match Ixdtf.new({ timestamp, zone: Some({ critical: Bool.True, identifier: Named("Synthetic/Archive") }), tags: [] }) {
		Ok(value) => value
		Err(_) => crash "Valid synthetic snapshot declaration rejected"
	}
	# Both tables resolve the queried point identically. Reusing the same name,
	# version and bounds must not erase their differing future microsecond data.
	validity = model_span(coordinate - 1, coordinate + 4)
	var snapshots = []
	for later_offset in [1.I32, 2] {
		rules = match ZoneRules.new_bounded("Synthetic/Archive", "same-version", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(coordinate + 1), offset: FixedOffset.from_seconds(later_offset) }], { minimum: 0, maximum: 2 }) {
			Ok(value) => value
			Err(_) => crash "Microsecond synthetic transition fixture rejected"
		}
		snapshot = match Ixdtf.resolve(source, Some(rules)) {
			Ok(value) => value
			Err(_) => crash "Synthetic point before transition failed"
		}
		restored = check_snapshot_persistence(snapshot, coordinate, 0)
		retained = match Ixdtf.Snapshot.context(restored) {
			Some(value) => value
			None => crash "Restored named snapshot lost its rules"
		}
		if ZoneRules.offset_at(retained, PosixBoundary.from_microseconds(coordinate + 1)) != Ok(FixedOffset.from_seconds(later_offset)) or
			ZoneRules.validity(retained) != validity {
			crash "Snapshot persistence preserved only the queried point, not transition/validity evidence"
		}
		snapshots = snapshots.append(restored)
	}
	first = match snapshots.get(0) {
		Ok(value) => value
		Err(_) => crash "Two-table model invariant"
	}
	second = match snapshots.get(1) {
		Ok(value) => value
		Err(_) => crash "Two-table model invariant"
	}
	if first == second or !Ixdtf.Snapshot.same_position(first, second) {
		crash "Snapshot evidence equality confused with compatible-axis position"
	}
	keyed = Dict.insert(Dict.insert(Dict.empty(), first, 1.U8), second, 2.U8)
	if Dict.get(keyed, first) != Ok(1) or Dict.get(keyed, second) != Ok(2) {
		crash "Snapshot equality/hash erased distinct immutable rule tables"
	}
}

# R07/R09/R14: the two raw offset segments have independently known preimages.
# Shifting their origin through the generated range does not change the model.
# Mixed Gregorian/Julian endpoint declarations retain identity despite denoting
# positions on the same local coordinate axis.
check_civil_snapshot_persistence = |origin| {
	fold = civil_fixture_rules(origin, 2, 0)
	gap = civil_fixture_rules(origin, 0, 2)
	lower = civil_fixture_label(origin + 500000, Gregorian)
	upper = civil_fixture_label(origin + 750000, Julian)
	expected = Coverage.from_spans([model_span(origin - 1500000, origin - 1250000), model_span(origin + 500000, origin + 750000)])
	for choice in [{ policy: First, position: origin - 1500000, offset: 2.I32 }, { policy: Last, position: origin + 500000, offset: 0.I32 }, { policy: MatchingOffset(FixedOffset.from_seconds(2)), position: origin - 1500000, offset: 2.I32 }, { policy: MatchingOffset(FixedOffset.from_seconds(0)), position: origin + 500000, offset: 0.I32 }] {
		snapshot = match ResolvedBoundary.resolve(fold, lower, choice.policy) {
			Ok(found) => found
			Err(_) => crash "Independent fold occurrence fixture rejected"
		}
		replay = match replay_snapshot_value(ResolvedBoundary(snapshot)) {
			ResolvedBoundary(found) => found
			_ => crash "Civil boundary persistence changed nominal kind"
		}
		if ResolvedBoundary.boundary(replay) != PosixBoundary.from_microseconds(choice.position) or
			ResolvedBoundary.offset(replay) != FixedOffset.from_seconds(choice.offset) or
				ResolvedBoundary.source(replay) != lower or ResolvedBoundary.policy(replay) != choice.policy or
					ZoneRules.definition(ResolvedBoundary.rules(replay)) != ZoneRules.definition(fold) or replay != snapshot {
			crash "Civil boundary persistence changed independently modeled occurrence or policy"
		}
		source = Explanation.new(ResolvedBoundary(replay))
		if explanation_fact(source, 0) != CivilBoundaryDescription({ source: lower, policy: choice.policy, boundary: PosixBoundary.from_microseconds(choice.position), offset: FixedOffset.from_seconds(choice.offset) }) or Explanation.fact_count(source) != 2 {
			crash "Boundary explanation lost modeled occurrence, calendar or policy"
		}
		check_civil_context(source, 1, fold)
		check_declaration_limits(source, 1)
	}
	match ResolvedBoundary.resolve(gap, lower, First) {
		Err(Gap) => {}
		_ => crash "Gap occurrence invented a resolved boundary"
	}
	for fixture in [{ rules: fold, extent: expected }, { rules: gap, extent: Coverage.empty }] {
		snapshot = match ResolvedSelection.resolve(fixture.rules, lower, upper) {
			Ok(found) => found
			Err(_) => crash "Independent civil selection fixture rejected"
		}
		replay = match replay_snapshot_value(ResolvedSelection(snapshot)) {
			ResolvedSelection(found) => found
			_ => crash "Civil selection persistence changed nominal kind"
		}
		if ResolvedSelection.coverage(replay) != fixture.extent or ResolvedSelection.start(replay) != lower or
			ResolvedSelection.end(replay) != upper or
				ZoneRules.definition(ResolvedSelection.rules(replay)) != ZoneRules.definition(fixture.rules) or replay != snapshot {
			crash "Civil selection persistence erased empty/disconnected coverage or endpoint calendar identity"
		}
		members = if fixture.extent == Coverage.empty {
			[]
		} else {
			[model_span(origin - 1500000, origin - 1250000), model_span(origin + 500000, origin + 750000)]
		}
		check_civil_explanation(replay, lower, upper, fixture.rules, members)
	}
}

civil_fixture_rules = |origin, initial, after| match ZoneRules.new_bounded("Synthetic/CivilPersistence", "v1", model_span(origin - 4000000, origin + 4000000), FixedOffset.from_seconds(initial), [{ at: PosixBoundary.from_microseconds(origin), offset: FixedOffset.from_seconds(after) }], { minimum: 0, maximum: 2 }) {
	Ok(found) => found
	Err(_) => crash "Valid two-segment civil fixture rules"
}

civil_fixture_label = |coordinate, calendar| match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(coordinate), calendar) {
	Ok(found) => found
	Err(_) => crash "Bounded civil fixture label"
}

replay_snapshot_value = |value| {
	envelope = match Persistence.new(value) {
		Ok(found) => found
		Err(_) => crash "Small civil snapshot persistence rejected"
	}
	text = Persistence.to_text(envelope)
	replay = match Persistence.parse(text) {
		Ok(found) => found
		Err(_) => crash "Civil snapshot canonical persistence failed"
	}
	if Persistence.to_text(replay) != text {
		crash "Civil snapshot persistence is not canonically stable"
	}
	Persistence.value(replay)
}

# R07/R09/R14: raw segment preimages above are the member oracle; rendering
# completion is deliberately checked separately from interpretation completion.
check_civil_explanation = |snapshot, lower, upper, rules, members| {
	coverage_source = Explanation.new(Coverage(ResolvedSelection.coverage(snapshot)))
	source = Explanation.new(ResolvedSelection(snapshot))
	count = members.len()
	if explanation_fact(coverage_source, 0) != CoverageDescription({ member_count: count }) or
		explanation_fact(source, 0) != CivilSelectionDescription({ start: lower, end: upper, member_count: count }) or
			Explanation.fact_count(coverage_source) != count + 1 or Explanation.fact_count(source) != count + 2 {
		crash "Complete coverage explanation changed independent membership or endpoint identity"
	}
	check_civil_context(source, 1, rules)
	var index = 0.U64
	for span in members {
		expected = CoverageMember({ index, span })
		if explanation_fact(coverage_source, index + 1) != expected or explanation_fact(source, index + 2) != expected {
			crash "Coverage explanation changed independent half-open member"
		}
		index = index + 1
	}
	check_declaration_limits(coverage_source, 1)
	check_declaration_limits(source, 1)
	cursor = match ZoneRules.selection_cursor(rules, lower, upper) {
		Ok(value) => value
		Err(_) => crash "Bounded selection cursor fixture rejected"
	}
	for limit in [0.U64, 1, 8] {
		batch = match ResolvedSelection.collect(cursor, { max_segments: limit, max_members: 8 }) {
			Ok(value) => value
			Err(_) => crash "Bounded selection evaluation fixture rejected"
		}
		batch_source = Explanation.new(SelectionBatch(batch))
		status = match batch.status {
			Limited(progress) => {
				if limit == 8 or progress.reason != WorkLimit or
					explanation_fact(batch_source, 1) != LocalSelectionDescription({ start: lower, end: upper }) or
						Explanation.fact_count(batch_source) != 3 {
					crash "Incomplete evaluation fabricated complete coverage facts"
				}
				check_civil_context(batch_source, 2, rules)
				Limited(WorkLimit)
			}
			Complete(done) => {
				if limit < 2 or ResolvedSelection.coverage(done) != ResolvedSelection.coverage(snapshot) or
					explanation_fact(batch_source, 1) != CivilSelectionDescription({ start: lower, end: upper, member_count: count }) or
						Explanation.fact_count(batch_source) != count + 3 {
					crash "Complete evaluation lost independently modeled empty/disconnected result"
				}
				check_civil_context(batch_source, 2, rules)
				var member_index = 0.U64
				for span in members {
					if explanation_fact(batch_source, member_index + 3) != CoverageMember({ index: member_index, span }) {
						crash "Complete batch explanation changed raw modeled member"
					}
					member_index = member_index + 1
				}
				Complete
			}
		}
		if explanation_fact(batch_source, 0) != SelectionEvaluation({ status, segments: batch.segments, buffered: batch.buffered }) or
			(limit == 0 and (batch.segments != 0 or batch.buffered != 0)) {
			crash "Batch explanation changed work state"
		}
		# This requires Complete rendering even for Limited(WorkLimit) evaluation.
		check_declaration_limits(batch_source, 1)
	}
}

check_civil_context = |source, index, rules| {
	definition = ZoneRules.definition(rules)
	if explanation_fact(source, index) != Context({ name: definition.name, version: definition.version, validity: definition.validity, provenance: definition.provenance }) {
		crash "Civil explanation changed retained immutable context metadata"
	}
}

# R01/R02/R14: direct constructor inputs complement the generated parser path.
# Decimal strings padded by prepending zeros are independent of the formatter's
# digit-writing buffer. Every case covers all widths and offset assertions;
# generated clock fields ensure runtime values and both extreme years recur.
check_timestamp_format_limits = |input| {
	hour = input.seconds // 3600
	minute = (input.seconds // 60) % 60
	second = input.seconds % 60
	var scale = 1.U32
	for digits in [0.U8, 1, 2, 3, 4, 5, 6] {
		for variant in [0.U8, 1, 2, 3] {
			year = if (variant + input.qualifier) % 2 == 0 {
				0.I64
			} else {
				9999.I64
			}
			fraction = if digits == 0 {
				0.U32
			} else {
				match variant {
					0 => 0
					1 => 1
					2 => if digits < 2 {
						0
					} else {
						10
					}
					_ => scale - 1
				}
			}
			offset = match variant {
				0 => UnassertedUtc
				1 => Asserted(FixedOffset.from_seconds(0))
				2 => Asserted(FixedOffset.from_seconds(86340))
				_ => Asserted(FixedOffset.from_seconds(-86340))
			}
			suffix = match variant {
				0 => "Z"
				1 => "+00:00"
				2 => "+23:59"
				_ => "-23:59"
			}
			date = match GregorianDate.from_fields({ year, month: 1, day: 1 }) {
				Ok(value) => value
				Err(_) => crash "Formatter boundary year fixture rejected"
			}
			clock = match ClockTime.from_fields({ hour: hour.to_u8_wrap(), minute: minute.to_u8_wrap(), second: second.to_u8_wrap(), microsecond: fraction * (1000000 // scale) }) {
				Ok(value) => value
				Err(_) => crash "Formatter exact-width clock fixture rejected"
			}
			parts = { date, clock, fraction_digits: digits, offset }
			value = match OffsetTimestamp.new(parts) {
				Ok(found) => found
				Err(_) => crash "Valid direct formatter input rejected"
			}
			fraction_text = if digits == 0 {
				""
			} else {
				".${pad(fraction.to_u64(), digits.to_u64())}"
			}
			expected = "${pad(year.to_u64_wrap(), 4)}-01-01T${pad(hour.to_u64(), 2)}:${pad(minute.to_u64(), 2)}:${pad(second.to_u64(), 2)}${fraction_text}${suffix}"
			retained = [value, value]
			for shared in retained {
				if OffsetTimestamp.to_text(shared) != expected or OffsetTimestamp.parts(shared) != parts {
					crash "Timestamp formatter changed exact boundary-year fields, precision or offset assertion"
				}
			}
			if OffsetTimestamp.parse(expected) != Ok(value) or OffsetTimestamp.to_text(value) != expected {
				crash "Formatting retained value changed its independent canonical text"
			}
		}
		scale = scale * 10
	}
}
