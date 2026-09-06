import fuzz.Fuzz
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
