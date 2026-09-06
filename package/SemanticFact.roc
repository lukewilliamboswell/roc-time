import GregorianDate
import Calendar
import CalendarDate
import ClockTime
import LocalDateTime
import FixedOffset
import PosixBoundary
import PosixSpan

## Typed semantic observations for inspection and bounded explanation. Facts
## carry supplied information; constructing one does not validate a temporal
## declaration or bind an interpretation. Native fact visitors provide those
## guarantees from their validated values and snapshots.
## Summary is fixed-size diagnostic text (at most 256 UTF-8 bytes), without
## enumerating children, copying arbitrary annotations or inspecting rule data.
## Full renderers use kind with explicit text/work limits. No persistence format.
SemanticFact :: { value : Kind }.{
	Resolution : [Year, Month, Day, Hour, Minute, Second, Fraction(U8)]
	Offset : [UnassertedUtc, Asserted(FixedOffset)]

	## Fields/clock carry the canonical lower label; resolution identifies which
	## components were supplied. Lower components filled by native construction
	## are not additional source assertions and must not be rendered as such.
	CalendarData : { kind : [CalendarValue, QualifiedCalendarValue, EdtfDate], calendar : Calendar, fields : CalendarDate.Fields, clock : ClockTime.Fields, resolution : Resolution, qualification_count : U64 }
	TimestampData : { kind : [OffsetTimestamp, Ixdtf], local : LocalDateTime, fraction_digits : U8, offset : Offset, zone_present : Bool, annotation_count : U64 }
	QualificationData : { scope : [Whole, Year, Month, Day, Hour, Minute, Second, Fraction], qualifier : [Uncertain, Approximate, UncertainApproximate] }
	ZoneData : { critical : Bool, identifier : [Named(Str), Numeric(FixedOffset)] }
	AnnotationData : { critical : Bool, key : Str, value : Str }

	## Local is the snapshot's stored Gregorian projection, not a claim that its
	## preferred calendar is supported. The separate Presentation fact states that.
	PositionData : { boundary : PosixBoundary, offset : FixedOffset, local : LocalDateTime }
	ContextData : { name : Str, version : Str, validity : PosixSpan, provenance : [Supplied, DatabaseSource({ requested_name : Str, canonical_name : Str, source_digest : Str, profile : Str })] }
	ExactIntervalData : { span : PosixSpan }
	OffsetEndpointData : { role : [Start, End], local : LocalDateTime, fraction_digits : U8, offset : Offset }
	RfcDateTimeData : { role : [Standalone, Start, End], local : LocalDateTime, form : [Utc, Local] }
	RfcDurationData : { role : [Standalone, PeriodEnding, RecurrenceEnding], days : I64, seconds : I64 }
	RfcPeriodData : { form : [Utc, Local], start : LocalDateTime, ending : [Endpoint(LocalDateTime), Duration({ days : I64, seconds : I64 })] }
	CoverageData : { member_count : U64 }
	CoverageMemberData : { index : U64, span : PosixSpan }
	CivilBoundaryData : { source : LocalDateTime, policy : [RequireUnique, First, Last, MatchingOffset(FixedOffset)], boundary : PosixBoundary, offset : FixedOffset }
	CivilSelectionData : { start : LocalDateTime, end : LocalDateTime, member_count : U64 }
	LocalSelectionData : { start : LocalDateTime, end : LocalDateTime }
	SelectionEvaluationData : { status : [Complete, Limited([WorkLimit, BufferLimit])], segments : U64, buffered : U64 }
	Weekday : [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
	RecurrenceAnchor : [Date(GregorianDate), Local(LocalDateTime)]
	RecurrenceFrequency : [Daily, Weekly, Monthly, Yearly, Hourly, Minutely, Secondly]
	RecurrenceData : { kind : [DateRecurrence, TimedRecurrence], anchor : RecurrenceAnchor, frequency : RecurrenceFrequency, interval : I64, week_start : [None, Some(Weekday)], selector_count : U64, inclusion_count : U64, exclusion_count : U64 }
	RecurrenceEnd : [Forever, Count(U64), UntilDate(GregorianDate), UntilLocal(LocalDateTime), UntilBoundary(PosixBoundary)]
	Selector : [Month(U8), MonthDay(I8), YearDay(I16), WeekNo(I8), Weekday({ ordinal : I8, weekday : Weekday }), SetPosition(I16), Hour(U8), Minute(U8), Second(U8), Microsecond(U32)]
	RecurrenceExceptionData : { kind : [Inclusion, Exclusion], source : RecurrenceAnchor }
	RecurrencePolicyData : { context : [Required, FixedUtc], occurrence : [CallerSupplied, First], gap : [CallerSupplied, UseOffsetBeforeGap] }
	RfcTimedRuleData : { mode : [Utc, Floating, Zoned], period_count : U64 }
	Kind : [RecurrenceDescription(RecurrenceData), RecurrenceTermination(RecurrenceEnd), RecurrenceSelector(Selector), RecurrenceException(RecurrenceExceptionData), RecurrencePolicy(RecurrencePolicyData), RfcTimedRuleDescription(RfcTimedRuleData), CoverageDescription(CoverageData), CoverageMember(CoverageMemberData), CivilBoundaryDescription(CivilBoundaryData), CivilSelectionDescription(CivilSelectionData), LocalSelectionDescription(LocalSelectionData), SelectionEvaluation(SelectionEvaluationData), ExactIntervalDescription(ExactIntervalData), OffsetEndpoint(OffsetEndpointData), RfcDateTimeDescription(RfcDateTimeData), RfcDurationDescription(RfcDurationData), RfcPeriodDescription(RfcPeriodData), CalendarDescription(CalendarData), TimestampDescription(TimestampData), Qualification(QualificationData), Requirement([ZoneContext, UncertaintyModel]), ZoneAnnotation(ZoneData), Annotation(AnnotationData), ResolvedPosition(PositionData), Context(ContextData), Presentation([Gregorian, UnsupportedCalendar(Str)])]
	new : Kind -> SemanticFact
	new = |kind| { value: kind }
	kind : SemanticFact -> Kind
	kind = |fact| fact.value

	summary : SemanticFact -> Str
	summary = |fact| match fact.value {
		RecurrenceDescription(data) => {
			anchor = match data.anchor {
				Date(date) => Str.inspect(date)
				Local(local) => local_text(local, 6)
			}
			"${Str.inspect(data.kind)}(anchor=${anchor}, frequency=${Str.inspect(data.frequency)}, step=${data.interval.to_str()}, selectors=${data.selector_count.to_str()}, included=${data.inclusion_count.to_str()}, excluded=${data.exclusion_count.to_str()})"
		}
		RecurrenceTermination(ending) => match ending {
			Forever => "Termination(Forever)"
			Count(count) => "Termination(Count(${count.to_str()}))"
			UntilDate(date) => "Termination(UntilDate(${Str.inspect(date)}))"
			UntilLocal(local) => "Termination(UntilLocal(${local_text(local, 6)}))"
			UntilBoundary(boundary) => "Termination(UntilBoundary(${PosixBoundary.to_microseconds(boundary).to_str()} POSIX microseconds))"
		}
		RecurrenceSelector(selector) => "Selector(${Str.inspect(selector)})"
		RecurrenceException(_) => "Recurrence exception"
		RecurrencePolicy(_) => "Recurrence interpretation policy"
		RfcTimedRuleDescription(data) => "RfcTimedRule(mode=${Str.inspect(data.mode)}, periods=${data.period_count.to_str()}, unresolved)"
		CoverageDescription(data) => "Coverage(members=${data.member_count.to_str()})"
		CoverageMember(data) => "CoverageMember(index=${data.index.to_str()}, span=${Str.inspect(data.span)})"
		CivilBoundaryDescription(data) => "ResolvedBoundary(source=${local_text(data.source, 6)}, policy=${Str.inspect(data.policy)}, boundary=${Str.inspect(data.boundary)}, offset=${FixedOffset.to_seconds(data.offset).to_str()} seconds)"
		CivilSelectionDescription(data) => "ResolvedSelection(start=${local_text(data.start, 6)}, end=${local_text(data.end, 6)}, members=${data.member_count.to_str()})"
		LocalSelectionDescription(data) => "LocalSelection(start=${local_text(data.start, 6)}, end=${local_text(data.end, 6)})"
		SelectionEvaluation(data) => "SelectionEvaluation(status=${Str.inspect(data.status)}, segments=${data.segments.to_str()}, buffered=${data.buffered.to_str()})"
		ExactIntervalDescription(data) => "ExactInterval(${Str.inspect(data.span)})"
		OffsetEndpoint(data) => {
			offset = match data.offset {
				UnassertedUtc => "unasserted UTC"
				Asserted(fixed) => "asserted ${FixedOffset.to_seconds(fixed).to_str()} seconds"
			}
			"OffsetEndpoint(role=${Str.inspect(data.role)}, local=${local_text(data.local, data.fraction_digits)}, fraction_digits=${data.fraction_digits.to_str()}, offset=${offset})"
		}
		RfcDateTimeDescription(data) => "RfcDateTime(role=${Str.inspect(data.role)}, form=${Str.inspect(data.form)}, label=${local_text(data.local, 0)})"
		RfcDurationDescription(data) => "RfcDuration(role=${Str.inspect(data.role)}, calendar_days=${data.days.to_str()}, coordinate_seconds=${data.seconds.to_str()})"
		RfcPeriodDescription(data) => {
			ending = match data.ending {
				Endpoint(local) => "endpoint=${local_text(local, 0)}"
				Duration(duration) => "calendar_days=${duration.days.to_str()}, coordinate_seconds=${duration.seconds.to_str()}"
			}
			"RfcPeriod(form=${Str.inspect(data.form)}, start=${local_text(data.start, 0)}, ${ending})"
		}
		CalendarDescription(data) => {
			name = match data.kind {
				CalendarValue => "CalendarValue"
				QualifiedCalendarValue => "QualifiedCalendarValue"
				EdtfDate => "EdtfDate"
			}
			date = date_text(data.fields, data.resolution)
			time = match data.resolution {
				Year => ""
				Month => ""
				Day => ""
				Hour => "T${two(data.clock.hour)}"
				Minute => "T${two(data.clock.hour)}:${two(data.clock.minute)}"
				Second => "T${clock_text(data.clock, 0)}"
				Fraction(digits) => "T${clock_text(data.clock, digits)}"
			}
			"${name}(calendar=${Calendar.to_name(data.calendar)}, value=${date}${time}, resolution=${Str.inspect(data.resolution)}, qualifications=${data.qualification_count.to_str()})"
		}
		TimestampDescription(data) => {
			name = match data.kind {
				OffsetTimestamp => "OffsetTimestamp"
				Ixdtf => "Ixdtf"
			}
			date = LocalDateTime.date(data.local)
			fields = CalendarDate.to_fields(date)
			clock = ClockTime.to_fields(LocalDateTime.clock(data.local))
			offset = match data.offset {
				UnassertedUtc => "Z"
				Asserted(fixed) => "[asserted_offset_seconds=${FixedOffset.to_seconds(fixed).to_str()}]"
			}
			"${name}(calendar=${Calendar.to_name(CalendarDate.calendar(date))}, value=${date_text(fields, Day)}T${clock_text(clock, data.fraction_digits)}${offset}, zone=${
				if data.zone_present {
					"present"
				} else {
					"absent"
				}
			}, tags=${data.annotation_count.to_str()})"
		}
		Qualification(data) => "Qualification(scope=${Str.inspect(data.scope)}, qualifier=${Str.inspect(data.qualifier)})"
		Requirement(ZoneContext) => "Requirement(zone context)"
		Requirement(UncertaintyModel) => "Requirement(uncertainty model)"
		ZoneAnnotation(_) => "ZoneAnnotation(details require bounded rendering)"
		Annotation(_) => "Annotation(details require bounded rendering)"
		ResolvedPosition(data) => "ResolvedPosition(${Str.inspect(data.boundary)}, offset=${Str.inspect(data.offset)})"
		Context(_) => "Context(details require bounded rendering)"
		Presentation(Gregorian) => "Presentation(Gregorian)"
		Presentation(UnsupportedCalendar(_)) => "Presentation(unsupported calendar)"
	}
	is_eq : SemanticFact, SemanticFact -> Bool
	is_eq = |a, b| a.value == b.value
	to_inspect : SemanticFact -> Str
	to_inspect = summary
}

date_text = |fields, resolution| {
	year = fields.year.to_str()
	match resolution {
		Year => year
		Month => "${year}-${two(fields.month)}"
		_ => "${year}-${two(fields.month)}-${two(fields.day)}"
	}
}

two : U8 -> Str
two = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}

clock_text = |clock, digits| {
	base = "${two(clock.hour)}:${two(clock.minute)}:${two(clock.second)}"
	if digits > 6 {
		return "${base}[microsecond=${clock.microsecond.to_str()}, digits=${digits.to_str()}]"
	}
	var divisor = 1.U32
	var remaining = 6.U8 - digits
	while remaining > 0 {
		divisor = divisor * 10
		remaining = remaining - 1
	}
	if U32.rem_by(clock.microsecond, divisor) != 0 or clock.microsecond > 999999 {
		return "${base}[microsecond=${clock.microsecond.to_str()}, digits=${digits.to_str()}]"
	}
	if digits == 0 {
		return base
	}
	fraction = U32.div_trunc_by(clock.microsecond, divisor).to_str()
	"${base}.${"0".repeat(digits.to_u64() - fraction.count_utf8_bytes())}${fraction}"
}

expect {
	# Arbitrary text stays outside fixed summaries even for publicly built facts.
	fact = SemanticFact.new(Annotation({ critical: True, key: "x".repeat(10000), value: "y".repeat(10000) }))
	SemanticFact.summary(fact).count_utf8_bytes() < 256
}
expect {
	data = { kind: QualifiedCalendarValue, calendar: Gregorian, fields: { year: I64.lowest, month: 255.U8, day: 255.U8 }, clock: { hour: 255.U8, minute: 255.U8, second: 255.U8, microsecond: U32.highest }, resolution: Fraction(255.U8), qualification_count: U64.highest }
	SemanticFact.summary(SemanticFact.new(CalendarDescription(data))).count_utf8_bytes() <= 256
}

expect {
	local = FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(0), Gregorian)?
	position = SemanticFact.new(ResolvedPosition({ boundary: PosixBoundary.from_microseconds(I64.lowest), offset: FixedOffset.from_seconds(I32.lowest), local }))
	timestamp = SemanticFact.new(TimestampDescription({ kind: OffsetTimestamp, local, fraction_digits: 255, offset: Asserted(FixedOffset.from_seconds(I32.lowest)), zone_present: True, annotation_count: U64.highest }))
	SemanticFact.summary(position).count_utf8_bytes() <= 160 and SemanticFact.summary(timestamp).count_utf8_bytes() <= 256
}

local_text = |local, digits| {
	date = LocalDateTime.date(local)
	"${Calendar.to_name(CalendarDate.calendar(date))}:${date_text(CalendarDate.to_fields(date), Day)}T${clock_text(ClockTime.to_fields(LocalDateTime.clock(local)), digits)}"
}

expect {
	local = FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(-1), Gregorian)?
	span = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
	SemanticFact.summary(
		SemanticFact.new(
			ExactIntervalDescription(
				{ span: span },
			),
		),
	).count_utf8_bytes() <= 160 and
		SemanticFact.summary(SemanticFact.new(RfcPeriodDescription({ form: Local, start: local, ending: Duration({ days: I64.lowest, seconds: I64.highest }) }))).count_utf8_bytes() <= 256 and
			SemanticFact.summary(SemanticFact.new(OffsetEndpoint({ role: End, local, fraction_digits: 255, offset: Asserted(FixedOffset.from_seconds(I32.lowest)) }))).count_utf8_bytes() <= 256
}

expect {
	date = CalendarDate.from_fields(Julian, { year: -2147483648, month: 12, day: 31 })?
	clock = ClockTime.from_fields({ hour: 23, minute: 59, second: 59, microsecond: 999999 })?
	local = LocalDateTime.new(date, clock)
	boundary = SemanticFact.new(CivilBoundaryDescription({ source: local, policy: MatchingOffset(FixedOffset.from_seconds(I32.lowest)), boundary: PosixBoundary.from_microseconds(I64.lowest), offset: FixedOffset.from_seconds(I32.lowest) }))
	selection = SemanticFact.new(CivilSelectionDescription({ start: local, end: local, member_count: U64.highest }))
	evaluation = SemanticFact.new(SelectionEvaluation({ status: Limited(BufferLimit), segments: U64.highest, buffered: U64.highest }))
	SemanticFact.summary(boundary).count_utf8_bytes() <= 256 and SemanticFact.summary(selection).count_utf8_bytes() <= 256 and SemanticFact.summary(evaluation).count_utf8_bytes() <= 256
}
