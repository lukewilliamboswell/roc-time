import CalendarValue
import QualifiedCalendarValue
import EdtfDate
import OffsetTimestamp
import Ixdtf
import SemanticFact
import CalendarDate
import LocalDateTime
import ClockTime
import FixedOffset
import PosixBoundary
import PosixSpan

## Bounded explanation of descriptions and already-bound interpretation results.
## Typed facts come directly from the source; rendering never resolves zones,
## lowers calendar selections, invents tolerances or parses diagnostic text.
## Semantic status is carried by the facts; Report.status describes rendering
## completeness only. Caller limits bound visited facts and UTF-8 output bytes.
## Fact budgets count indexed fact accesses. A snapshot presentation fact may
## inspect at most 32 source annotations; no fact access traverses zone rules.
## Each embedded text field is previewed to 256 bytes before formatting, using
## UTF-8 boundaries and a visible ellipsis. TextLimit reports such previews.
##
## Zero fact/byte budgets visit no facts. A line that exceeds the remaining byte
## budget emits a UTF-8 prefix plus "..." when at least three bytes remain, then
## reports ByteLimit. ByteLimit takes precedence over field-preview truncation;
## TextLimit takes precedence over FactLimit when both affected the report.
Explanation :: { source : Source }.{
	Source : [CalendarValue(CalendarValue), QualifiedCalendarValue(QualifiedCalendarValue), EdtfDate(EdtfDate), OffsetTimestamp(OffsetTimestamp), Ixdtf(Ixdtf), Snapshot(Ixdtf.Snapshot)]
	Budget : { max_facts : U64, max_utf8_bytes : U64 }
	Report : { text : Str, status : [Complete, Limited([FactLimit, ByteLimit, TextLimit])], visited_facts : U64, total_facts : U64 }
	new : Source -> Explanation
	new = |source| { source: source }
	fact_count : Explanation -> U64
	fact_count = |value| match value.source {
		CalendarValue(v) => CalendarValue.fact_count(v)
		QualifiedCalendarValue(v) => QualifiedCalendarValue.fact_count(v)
		EdtfDate(v) => EdtfDate.fact_count(v)
		OffsetTimestamp(v) => OffsetTimestamp.fact_count(v)
		Ixdtf(v) => Ixdtf.fact_count(v)
		Snapshot(v) => Ixdtf.Snapshot.fact_count(v)
	}
	fact_at : Explanation, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| match value.source {
		CalendarValue(v) => CalendarValue.fact_at(v, index)
		QualifiedCalendarValue(v) => QualifiedCalendarValue.fact_at(v, index)
		EdtfDate(v) => EdtfDate.fact_at(v, index)
		OffsetTimestamp(v) => OffsetTimestamp.fact_at(v, index)
		Ixdtf(v) => Ixdtf.fact_at(v, index)
		Snapshot(v) => Ixdtf.Snapshot.fact_at(v, index)
	}
	plain : Explanation, Budget -> Report
	plain = |value, budget| {
		total = fact_count(value)
		if total == 0 {
			return { text: "", status: Complete, visited_facts: 0, total_facts: 0 }
		}
		if budget.max_facts == 0 {
			return { text: "", status: Limited(FactLimit), visited_facts: 0, total_facts: total }
		}
		if budget.max_utf8_bytes == 0 {
			return { text: "", status: Limited(ByteLimit), visited_facts: 0, total_facts: total }
		}
		var index = 0.U64
		var text = ""
		var text_limited = Bool.False
		while index < total and index < budget.max_facts {
			fact = match fact_at(value, index) {
				Item(v) => v
				End => crash "Source fact count and indexed access invariant"
			}
			rendered = render(fact)
			line = if text.is_empty() {
				rendered.text
			} else {
				"\n${rendered.text}"
			}
			remaining = budget.max_utf8_bytes - text.count_utf8_bytes()
			index = index + 1
			if line.count_utf8_bytes() > remaining {
				part = preview(line, remaining)
				return { text: "${text}${part.text}", status: Limited(ByteLimit), visited_facts: index, total_facts: total }
			}
			text = "${text}${line}"
			text_limited = text_limited or rendered.clipped
			# No additional source query is made once the byte budget is exhausted.
			if text.count_utf8_bytes() == budget.max_utf8_bytes and index < total {
				return { text, status: Limited(ByteLimit), visited_facts: index, total_facts: total }
			}
		}
		status = if text_limited {
			Limited(TextLimit)
		} else if index < total {
			Limited(FactLimit)
		} else {
			Complete
		}
		{ text, status, visited_facts: index, total_facts: total }
	}
	to_inspect : Explanation -> Str
	to_inspect = |value| "Explanation(facts=${fact_count(value).to_str()})"
}

# Byte length and slices inspect at most four candidate UTF-8 boundaries. A
# prefix slice may share input storage; concatenated rendered output is bounded.
preview : Str, U64 -> { text : Str, clipped : Bool }
preview = |text, limit| {
	length = text.count_utf8_bytes()
	if length <= limit {
		return { text, clipped: False }
	}
	room = if limit >= 3 {
		limit - 3
	} else {
		limit
	}
	var end = room
	var prefix = ""
	var found = Bool.False
	while !found {
		match text.drop_last_bytes(length - end) {
			Ok(value) => {
				prefix = value
				found = True
			}
			Err(_) => {
				end = end - 1
			}
		}
	}
	{
		text: if limit >= 3 {
			"${prefix}..."
		} else {
			prefix
		},
		clipped: True,
	}
}

text_field = |text| {
	cut = preview(text, 256)
	{ text: Str.inspect(cut.text), clipped: cut.clipped }
}

render : SemanticFact -> { text : Str, clipped : Bool }
render = |fact| match SemanticFact.kind(fact) {
	CalendarDescription(data) => { text: "${Str.inspect(data.kind)}: ${Str.inspect(data.calendar)} calendar; supplied resolution ${Str.inspect(data.resolution)}; supplied ${calendar_fields(data.fields, data.clock, data.resolution)}; qualifications ${data.qualification_count.to_str()}.", clipped: False }
	TimestampDescription(data) => { text: "${Str.inspect(data.kind)}: instant declaration at ${local_fields(data.local, data.fraction_digits)}; ${offset_assertion(data.offset)}; zone annotation ${Str.inspect(data.zone_present)}; additional annotations ${data.annotation_count.to_str()}.", clipped: False }
	Qualification(data) => { text: "Qualification: ${Str.inspect(data.scope)} is ${Str.inspect(data.qualifier)}; no numeric tolerance is inferred.", clipped: False }
	Requirement(ZoneContext) => { text: "Interpretation requires explicit zone context.", clipped: False }
	Requirement(UncertaintyModel) => { text: "Interpretation requires an explicit uncertainty model; no numeric tolerance is inferred.", clipped: False }
	ZoneAnnotation(data) => {
		name = match data.identifier {
			Named(text) => text_field(text)
			Numeric(offset) => { text: "fixed offset ${FixedOffset.to_seconds(offset).to_str()} seconds", clipped: False }
		}
		{ text: "Zone annotation: ${name.text}; critical ${Str.inspect(data.critical)}.", clipped: name.clipped }
	}
	Annotation(data) => {
		key = text_field(data.key)
		value = text_field(data.value)
		{ text: "Annotation: ${key.text} = ${value.text}; critical ${Str.inspect(data.critical)}.", clipped: key.clipped or value.clipped }
	}
	ResolvedPosition(data) => { text: "Resolved instant: ${PosixBoundary.to_microseconds(data.boundary).to_str()} POSIX microseconds since 1970-01-01; stored Gregorian local label ${local_fields(data.local, 6)}; offset ${FixedOffset.to_seconds(data.offset).to_str()} seconds.", clipped: False }
	Presentation(Gregorian) => { text: "Presentation: Gregorian calendar is supported.", clipped: False }
	Presentation(UnsupportedCalendar(name)) => {
		value = text_field(name)
		{ text: "Presentation: calendar ${value.text} is unsupported; the resolved instant remains known.", clipped: value.clipped }
	}
	Context(data) => {
		name = text_field(data.name)
		version = text_field(data.version)
		provenance = match data.provenance {
			Supplied => { text: "supplied rules", clipped: False }
			DatabaseSource(source) => {
				requested = text_field(source.requested_name)
				canonical = text_field(source.canonical_name)
				digest = text_field(source.source_digest)
				profile = text_field(source.profile)
				{ text: "database requested ${requested.text}, canonical ${canonical.text}, digest ${digest.text}, profile ${profile.text}", clipped: requested.clipped or canonical.clipped or digest.clipped or profile.clipped }
			}
		}
		{ text: "Context: zone ${name.text}, version ${version.text}, validity [${PosixBoundary.to_microseconds(PosixSpan.start(data.validity)).to_str()}, ${PosixBoundary.to_microseconds(PosixSpan.end(data.validity)).to_str()}) POSIX microseconds; ${provenance.text}.", clipped: name.clipped or version.clipped or provenance.clipped }
	}
}

expect preview("ééé", 5) == { text: "é...", clipped: True }
expect preview("é", 1) == { text: "", clipped: True }
expect preview("abc", 3) == { text: "abc", clipped: False }
expect {
	value = Explanation.new(CalendarValue(CalendarValue.year(Gregorian, 2004)?))
	zero = Explanation.plain(value, { max_facts: 0, max_utf8_bytes: 4096 })
	empty = Explanation.plain(value, { max_facts: 10, max_utf8_bytes: 0 })
	tiny = Explanation.plain(value, { max_facts: 10, max_utf8_bytes: 3 })
	zero.visited_facts == 0 and zero.text == "" and zero.status == Limited(FactLimit) and empty.visited_facts == 0 and empty.text == "" and empty.status == Limited(ByteLimit) and tiny.text == "..." and tiny.status == Limited(ByteLimit)
}

# Render only supplied calendar fields. Filled constructor fields never imply
# additional precision. These helpers format typed facts, not backing records.
calendar_fields = |date, clock, resolution| {
	year = "year ${date.year.to_str()}"
	if resolution == Year {
		return year
	}
	month = "${year}, month ${date.month.to_str()}"
	if resolution == Month {
		return month
	}
	day = "${month}, day ${date.day.to_str()}"
	if resolution == Day {
		return day
	}
	hour = "${day}, hour ${clock.hour.to_str()}"
	if resolution == Hour {
		return hour
	}
	minute = "${hour}, minute ${clock.minute.to_str()}"
	if resolution == Minute {
		return minute
	}
	second = "${minute}, second ${clock.second.to_str()}"
	match resolution {
		Fraction(digits) => "${second}, fraction .${fraction_text(clock.microsecond, digits)} (${digits.to_str()} supplied digits)"
		_ => second
	}
}

local_fields : LocalDateTime, U8 -> Str
local_fields = |local, digits| {
	date = CalendarDate.to_fields(LocalDateTime.date(local))
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	"year ${date.year.to_str()}, month ${date.month.to_str()}, day ${date.day.to_str()}, ${clock.hour.to_str()}:${pad(clock.minute.to_str(), 2)}:${pad(clock.second.to_str(), 2)}${
		if digits == 0 {
			""
		} else {
			".${fraction_text(clock.microsecond, digits)}"
		}
	}"
}

fraction_text : U32, U8 -> Str
fraction_text = |micros, digits| {
	var divisor = 1.U32
	var remaining = 6.U8 - digits
	while remaining > 0 {
		divisor = divisor * 10
		remaining = remaining - 1
	}
	pad(U32.div_trunc_by(micros, divisor).to_str(), digits.to_u64())
}

pad = |text, width| if text.count_utf8_bytes() < width {
	"${"0".repeat(width - text.count_utf8_bytes())}${text}"
} else {
	text
}

offset_assertion = |offset| match offset {
	UnassertedUtc => "UTC instant known; no local-offset assertion"
	Asserted(value) => "asserted local offset ${FixedOffset.to_seconds(value).to_str()} seconds"
}

expect {
	report = Explanation.plain(Explanation.new(CalendarValue(CalendarValue.year(Gregorian, 2004)?)), { max_facts: 10, max_utf8_bytes: 4096 })
	report.status == Complete and report.text.contains("supplied year 2004") and !report.text.contains("month") and !report.text.contains("hour")
}
expect {
	date = CalendarDate.from_fields(Gregorian, { year: 2004, month: 6, day: 11 })?
	value = CalendarValue.fractional_second(date, { hour: 12, minute: 30, second: 0 }, { value: 120, digits: 3 })?
	report = Explanation.plain(Explanation.new(CalendarValue(value)), { max_facts: 10, max_utf8_bytes: 4096 })
	report.status == Complete and report.text.contains("fraction .120 (3 supplied digits)")
}
