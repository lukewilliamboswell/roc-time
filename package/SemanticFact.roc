import CalendarDescriptionText
import GregorianDate
import Calendar
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

	## Finest supplied calendar component; Fraction carries the supplied decimal digit count.
	Resolution : [Year, Month, Day, Hour, Minute, Second, Fraction(U8)]

	## Whether UTC was unasserted or a particular local offset was explicitly asserted.
	Offset : [UnassertedUtc, Asserted(FixedOffset)]

	## Fields/clock carry the canonical lower label; resolution identifies which
	## components were supplied. Lower components filled by native construction
	## are not additional source assertions and must not be rendered as such.
	CalendarData : { kind : [CalendarValue, QualifiedCalendarValue, EdtfDate], calendar : Calendar, fields : Calendar.Date.Fields, clock : ClockTime.Fields, resolution : Resolution, qualification_count : U64 }

	## Stored timestamp label, fractional precision and offset assertion, plus
	## zone/annotation counts. These fields alone do not bind a named zone.
	TimestampData : { kind : [OffsetTimestamp, Ixdtf], local : LocalDateTime, fraction_digits : U8, offset : Offset, zone_present : Bool, annotation_count : U64 }

	## One scoped uncertainty/approximation assertion, without a tolerance model.
	QualificationData : { scope : [Whole, Year, Month, Day, Hour, Minute, Second, Fraction, YearMonth], qualifier : [Uncertain, Approximate, UncertainApproximate] }

	## A named or numeric zone annotation and whether its interpretation is required.
	ZoneData : { critical : Bool, identifier : [Named(Str), Numeric(FixedOffset)] }

	## An annotation key/value and critical flag. Render text with explicit bounds.
	AnnotationData : { critical : Bool, key : Str, value : Str }

	## Local is the snapshot's stored Gregorian projection, not a claim that its
	## preferred calendar is supported. The separate Presentation fact states that.
	PositionData : { boundary : PosixBoundary, offset : FixedOffset, local : LocalDateTime }

	## Identity, finite validity and supplied/database provenance of retained rules.
	## Metadata does not replace the actual immutable transition rules.
	ContextData : { name : Str, version : Str, validity : PosixSpan, provenance : [Supplied, DatabaseSource({ requested_name : Str, canonical_name : Str, source_digest : Str, profile : Str })] }

	## The exact half-open POSIX span of an interval.
	ExactIntervalData : { span : PosixSpan }

	## An interval endpoint label with its role, fractional precision and offset assertion.
	OffsetEndpointData : { role : [Start, End], local : LocalDateTime, fraction_digits : U8, offset : Offset }

	## An iCalendar date-time label and its UTC/local form, optionally identifying
	## its role as a period endpoint. Local form alone supplies no zone context.
	ICalDateTimeData : { role : [Standalone, Start, End], local : LocalDateTime, form : [Utc, Local] }

	## An iCalendar duration retaining calendar days separately from coordinate
	## seconds, with its role in the surrounding declaration.
	ICalDurationData : { role : [Standalone, PeriodEnding, RecurrenceEnding], days : I64, seconds : I64 }

	## An iCalendar period retaining UTC/local form and the declared ending form:
	## an explicit endpoint or separate calendar-day/second duration components.
	ICalPeriodData : { form : [Utc, Local], start : LocalDateTime, ending : [Endpoint(LocalDateTime), Duration({ days : I64, seconds : I64 })] }

	## The cached number of canonical coverage members, without enumerating them.
	CoverageData : { member_count : U64 }

	## One canonical coverage span and its zero-based member index.
	CoverageMemberData : { index : U64, span : PosixSpan }

	## A retained civil label and occurrence policy with the resulting POSIX
	## coordinate and actual offset.
	CivilBoundaryData : { source : LocalDateTime, policy : [RequireUnique, First, Last, MatchingOffset(FixedOffset)], boundary : PosixBoundary, offset : FixedOffset }

	## The original half-open civil selection and its complete coverage member count.
	CivilSelectionData : { start : LocalDateTime, end : LocalDateTime, member_count : U64 }

	## The requested half-open civil bounds; this fact does not assert completed coverage.
	LocalSelectionData : { start : LocalDateTime, end : LocalDateTime }

	## Evaluation completeness, segment work for the batch, and retained member
	## count. A Limited status must not be interpreted as empty coverage.
	SelectionEvaluationData : { status : [Complete, Limited([WorkLimit, BufferLimit])], segments : U64, buffered : U64 }

	## Named weekdays for recurrence selectors and week-start metadata.
	Weekday : [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]

	## A date-only or local date-time recurrence anchor, preserving its coordinate domain.
	RecurrenceAnchor : [Date(GregorianDate), Local(LocalDateTime)]

	## The declared recurrence period unit; it does not specify elapsed spacing.
	RecurrenceFrequency : [Daily, Weekly, Monthly, Yearly, Hourly, Minutely, Secondly]

	## Stored recurrence anchor, frequency, interval, week start and declaration
	## counts. Reading this metadata does not generate occurrences.
	RecurrenceData : { kind : [DateRecurrence, TimedRecurrence], anchor : RecurrenceAnchor, frequency : RecurrenceFrequency, interval : I64, week_start : [None, Some(Weekday)], selector_count : U64, inclusion_count : U64, exclusion_count : U64 }

	## The rule termination and its domain. Count limits generated candidates
	## before exclusions; it is not a promised emitted-result count.
	RecurrenceEnd : [Forever, Count(U64), UntilDate(GregorianDate), UntilLocal(LocalDateTime), UntilBoundary(PosixBoundary)]

	## One effective recurrence selector, including normalized clock defaults.
	## These facts do not preserve whether a default appeared in source text.
	Selector : [Month(U8), MonthDay(I8), YearDay(I16), WeekNo(I8), Weekday({ ordinal : I8, weekday : Weekday }), SetPosition(I16), Hour(U8), Minute(U8), Second(U8), Microsecond(U32)]

	## One explicit inclusion or exclusion in the recurrence source-label domain.
	RecurrenceExceptionData : { kind : [Inclusion, Exclusion], source : RecurrenceAnchor }

	## The context and occurrence/gap policy required or fixed by a declaration.
	RecurrencePolicyData : { context : [Required, FixedUtc], occurrence : [CallerSupplied, First], gap : [CallerSupplied, UseOffsetBeforeGap] }

	## The iCalendar rule mode and explicit period count, before schedule evaluation.
	ICalTimedRuleData : { mode : [Utc, Floating, Zoned], period_count : U64 }

	## A civil description and its explicit zone requirement; no interpretation.
	calendar_value_fact_count : Calendar.Value -> U64
	calendar_value_fact_count = |_| 2

	## Constant-cost access through Calendar.Value.description; out-of-range is End.
	calendar_value_fact_at : Calendar.Value, U64 -> [End, Item(SemanticFact)]
	calendar_value_fact_at = |value, index| match index {
		0 => {
			data = Calendar.Value.description(value)
			Item(SemanticFact.new(CalendarDescription({ kind: CalendarValue, calendar: data.calendar, fields: data.fields, clock: data.clock, resolution: data.resolution, qualification_count: 0 })))
		}
		1 => Item(SemanticFact.new(Requirement(ZoneContext)))
		_ => End
	}

	## Typed observations of declarations, requirements, interpretation results and
	## evaluation status. Pattern-match these data for custom bounded presentation;
	## a fact is not a validated temporal value or an interchange envelope.
	Kind : [RecurrenceBoundaryExclusion(PosixBoundary), RecurrenceDescription(RecurrenceData), RecurrenceTermination(RecurrenceEnd), RecurrenceSelector(Selector), RecurrenceException(RecurrenceExceptionData), RecurrencePolicy(RecurrencePolicyData), ICalTimedRuleDescription(ICalTimedRuleData), CoverageDescription(CoverageData), CoverageMember(CoverageMemberData), CivilBoundaryDescription(CivilBoundaryData), CivilSelectionDescription(CivilSelectionData), LocalSelectionDescription(LocalSelectionData), SelectionEvaluation(SelectionEvaluationData), ExactIntervalDescription(ExactIntervalData), OffsetEndpoint(OffsetEndpointData), ICalDateTimeDescription(ICalDateTimeData), ICalDurationDescription(ICalDurationData), ICalPeriodDescription(ICalPeriodData), CalendarDescription(CalendarData), TimestampDescription(TimestampData), Qualification(QualificationData), Requirement([ZoneContext, UncertaintyModel]), ZoneAnnotation(ZoneData), Annotation(AnnotationData), ResolvedPosition(PositionData), Context(ContextData), Presentation([Gregorian, UnsupportedCalendar(Str)])]

	## Wrap a typed observation without validating its fields or resolving its meaning.
	## Use native values and their fact visitors when validation guarantees are needed.
	new : Kind -> SemanticFact
	new = |kind| { value: kind }

	## Return the typed observation for custom rendering or structured inspection.
	kind : SemanticFact -> Kind
	kind = |fact| fact.value

	## Produce at most 256 UTF-8 bytes of diagnostic summary without enumerating
	## children or copying arbitrary text fields. Use Explanation for bounded detail.
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
		RecurrenceBoundaryExclusion(boundary) => "Boundary exclusion(${PosixBoundary.to_microseconds(boundary).to_str()} POSIX microseconds)"
		RecurrencePolicy(_) => "Recurrence interpretation policy"
		ICalTimedRuleDescription(data) => "ICalTimedRule(mode=${Str.inspect(data.mode)}, periods=${data.period_count.to_str()}, unresolved)"
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
		ICalDateTimeDescription(data) => "ICalDateTime(role=${Str.inspect(data.role)}, form=${Str.inspect(data.form)}, label=${local_text(data.local, 0)})"
		ICalDurationDescription(data) => "ICalDuration(role=${Str.inspect(data.role)}, calendar_days=${data.days.to_str()}, coordinate_seconds=${data.seconds.to_str()})"
		ICalPeriodDescription(data) => {
			ending = match data.ending {
				Endpoint(local) => "endpoint=${local_text(local, 0)}"
				Duration(duration) => "calendar_days=${duration.days.to_str()}, coordinate_seconds=${duration.seconds.to_str()}"
			}
			"ICalPeriod(form=${Str.inspect(data.form)}, start=${local_text(data.start, 0)}, ${ending})"
		}
		CalendarDescription(data) => CalendarDescriptionText.summary({ kind: data.kind, calendar: Calendar.to_name(data.calendar), fields: data.fields, clock: data.clock, resolution: data.resolution, qualification_count: data.qualification_count })
		TimestampDescription(data) => {
			name = match data.kind {
				OffsetTimestamp => "OffsetTimestamp"
				Ixdtf => "Ixdtf"
			}
			date = LocalDateTime.date(data.local)
			fields = Calendar.Date.to_fields(date)
			clock = ClockTime.to_fields(LocalDateTime.clock(data.local))
			offset = match data.offset {
				UnassertedUtc => "Z"
				Asserted(fixed) => "[asserted_offset_seconds=${FixedOffset.to_seconds(fixed).to_str()}]"
			}
			"${name}(calendar=${Calendar.to_name(Calendar.Date.calendar(date))}, value=${date_text(fields, Day)}T${clock_text(clock, data.fraction_digits)}${offset}, zone=${
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

	## Compare the complete typed observation, including its tag and stored fields.
	is_eq : SemanticFact, SemanticFact -> Bool
	is_eq = |a, b| a.value == b.value

	## Return the same bounded diagnostic text as summary.
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
	var $divisor = 1.U32
	var $remaining = 6.U8 - digits
	while $remaining > 0 {
		$divisor = $divisor * 10
		$remaining = $remaining - 1
	}
	if U32.rem_by(clock.microsecond, $divisor) != 0 or clock.microsecond > 999999 {
		return "${base}[microsecond=${clock.microsecond.to_str()}, digits=${digits.to_str()}]"
	}
	if digits == 0 {
		return base
	}
	fraction = U32.div_trunc_by(clock.microsecond, $divisor).to_str()
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
	"${Calendar.to_name(Calendar.Date.calendar(date))}:${date_text(Calendar.Date.to_fields(date), Day)}T${clock_text(ClockTime.to_fields(LocalDateTime.clock(local)), digits)}"
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
		SemanticFact.summary(SemanticFact.new(ICalPeriodDescription({ form: Local, start: local, ending: Duration({ days: I64.lowest, seconds: I64.highest }) }))).count_utf8_bytes() <= 256 and
			SemanticFact.summary(SemanticFact.new(OffsetEndpoint({ role: End, local, fraction_digits: 255, offset: Asserted(FixedOffset.from_seconds(I32.lowest)) }))).count_utf8_bytes() <= 256
}

expect {
	date = Calendar.Date.from_fields(Julian, { year: -2147483648, month: 12, day: 31 })?
	clock = ClockTime.from_fields({ hour: 23, minute: 59, second: 59, microsecond: 999999 })?
	local = LocalDateTime.new(date, clock)
	boundary = SemanticFact.new(CivilBoundaryDescription({ source: local, policy: MatchingOffset(FixedOffset.from_seconds(I32.lowest)), boundary: PosixBoundary.from_microseconds(I64.lowest), offset: FixedOffset.from_seconds(I32.lowest) }))
	selection = SemanticFact.new(CivilSelectionDescription({ start: local, end: local, member_count: U64.highest }))
	evaluation = SemanticFact.new(SelectionEvaluation({ status: Limited(BufferLimit), segments: U64.highest, buffered: U64.highest }))
	SemanticFact.summary(boundary).count_utf8_bytes() <= 256 and SemanticFact.summary(selection).count_utf8_bytes() <= 256 and SemanticFact.summary(evaluation).count_utf8_bytes() <= 256
}
