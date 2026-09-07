import SemanticFact
import GregorianDate
import Calendar
import CalendarPattern
import ClockTime
import PosixDelta
import ICalDateTime
import ICalDuration
import TimedRecurrence
import TimedSchedule
import TimedOccurrence
import LocalDateTime
import PosixBoundary
import PosixSpan
import FixedOffset
import ZoneRules

## RFC 5545 section 3.3.9 PERIOD values, profile period-values-v1.
## Parse an extracted start/end or start/positive-duration value. Endpoint
## values share ICalDateTime's year, precision and leap-second profile. Both
## explicit endpoints must use the same UTC/local form; mixed forms are outside
## this profile. Property parameters, comma lists and ICS content lines belong
## to the calling adapter. Source spelling is not retained.
##
## Parsing visits at most 273 bytes and does no zone work. UTC endpoint order
## is checked immediately. Local endpoint order is checked after interpretation:
## increasing labels can resolve to equal or reversed boundaries near a gap.
## Canonical text preserves explicit-end versus duration intent.
## See the [reservation application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/reservations)
## for native rule execution with parsed period additions.
##
## ```roc
## import time.ICalPeriod
## expect {
##     value = ICalPeriod.parse("19970101T180000Z/PT5H30M")?
##     ICalPeriod.to_text(value) == "19970101T180000Z/PT19800S"
## }
## ```
ICalPeriod :: { start : ICalDateTime, ending : Ending }.{
	## Preserves whether the period ends at an explicit DATE-TIME or after a positive duration; these intents are not interchangeable near zone transitions.
	Ending : [End(ICalDateTime), Duration(ICalDuration)]
	## Utc interprets Z values without caller-supplied rules. Local supplies the immutable rules for local labels, including floating values interpreted by the caller.
	Context : [Utc, Local(ZoneRules)]
	## Reports which endpoint or duration failed, mixed UTC/local forms, invalid UTC ordering, syntax or input size.
	Error : [Malformed, TooLarge, Start(ICalDateTime.Error), End(ICalDateTime.Error), Duration(ICalDuration.Error), MixedForms, InvalidPeriod]

	## Decode one encoded string using this type's text parser.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : ICalPeriod, rest : state }, [InvalidICalPeriod(Error), Encoding(err), ..]))
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
				Err(error) => Err(InvalidICalPeriod(error))
			}
		}
	}

	## Encodes the canonical standard text as a string in the selected encoding; encoding failures pass through.
	encoder_for : encoding -> (ICalPeriod, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(ICalPeriod, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid ICalPeriod literal: ${Str.inspect(error)}"))
	}

	## Identifier of the supported text profile described above; it does not imply support for the entire standard.
	profile : Str
	profile = "rfc5545-period-values-v1"
	## Parses start/end or start/duration. UTC ordering is checked now; local ending order is checked when the period is interpreted.
	parse : Str -> Try(ICalPeriod, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 273 {
			return Err(TooLarge)
		}
		(left, right) = match text.split_on("/") {
			[a, b] => (a, b)
			_ => return Err(Malformed)
		}
		start = match ICalDateTime.parse(left) {
			Ok(value) => value
			Err(error) => return Err(Start(error))
		}
		first = right.to_utf8().get(0) ?? 0
		ending = if first == 80 or first == 112 or first == 43 or first == 45 {
			parsed_duration = match ICalDuration.parse(right) {
				Ok(value) => value
				Err(error) => return Err(Duration(error))
			}
			Duration(parsed_duration)
		} else {
			end = match ICalDateTime.parse(right) {
				Ok(value) => value
				Err(error) => return Err(End(error))
			}
			if ICalDateTime.form(start) != ICalDateTime.form(end) {
				return Err(MixedForms)
			}
			if ICalDateTime.form(start) == Utc and LocalDateTime.compare_position(ICalDateTime.local_label(start), ICalDateTime.local_label(end)) != LT {
				return Err(InvalidPeriod)
			}
			End(end)
		}
		Ok({ start, ending })
	}
	## The retained starting DATE-TIME declaration; no zone interpretation is performed.
	start : ICalPeriod -> ICalDateTime
	start = |value| value.start
	## The retained explicit endpoint or duration, preserving the original ending intent.
	ending : ICalPeriod -> Ending
	ending = |value| value.ending
	## Canonical start/end or start/duration value. Duration units may normalize, but explicit-end versus duration intent remains distinct.
	to_text : ICalPeriod -> Str
	to_text = |value| {
		end_text = match value.ending {
			End(end) => ICalDateTime.to_text(end)
			Duration(duration) => ICalDuration.to_text(duration)
		}
		"${ICalDateTime.to_text(value.start)}/${end_text}"
	}
	## Compares the start and ending declarations, including UTC/local form and duration-versus-endpoint intent.
	is_eq : ICalPeriod, ICalPeriod -> Bool
	is_eq = |a, b| a.start == b.start and a.ending == b.ending
	## Hashes the same declaration fields used by is_eq, so equal values are interchangeable as dictionary keys.
	to_hash : ICalPeriod, Hasher -> Hasher
	to_hash = |value, hasher| {
		base = value.start.to_hash(hasher)
		match value.ending {
			End(end) => end.to_hash((0.U8).to_hash(base))
			Duration(duration) => duration.to_hash((1.U8).to_hash(base))
		}
	}

	## These are source-declaration facts, not a resolved span. Local endpoint
	## ordering remains unresolved; a duration ending is not added to its start.
	fact_count : ICalPeriod -> U64
	fact_count = |value| if ICalDateTime.form(value.start) == Local {
		4
	} else {
		3
	}
	## Returns the zero-based semantic fact, or End when the index is outside fact_count. Facts describe meaning, not a serialized record.
	fact_at : ICalPeriod, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| {
		if index >= fact_count(value) {
			return End
		}
		form = ICalDateTime.form(value.start)
		match index {
			0 => {
				ending_fact = match value.ending {
					End(end) => Endpoint(ICalDateTime.local_label(end))
					Duration(duration) => Duration(ICalDuration.components(duration))
				}
				Item(SemanticFact.new(ICalPeriodDescription({ form, start: ICalDateTime.local_label(value.start), ending: ending_fact })))
			}
			1 => Item(SemanticFact.new(ICalDateTimeDescription({ role: Start, local: ICalDateTime.local_label(value.start), form })))
			2 => match value.ending {
				End(end) => Item(SemanticFact.new(ICalDateTimeDescription({ role: End, local: ICalDateTime.local_label(end), form })))
				Duration(duration) => {
					parts = ICalDuration.components(duration)
					Item(SemanticFact.new(ICalDurationDescription({ role: PeriodEnding, days: parts.days, seconds: parts.seconds })))
				}
			}
			_ => Item(SemanticFact.new(Requirement(ZoneContext)))
		}
	}
	## A concise semantic summary for debugging. Use the standard text encoder for storage or interchange.
	to_inspect : ICalPeriod -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "RFC period has a first semantic fact"
	}

	## Add at most 4096 PERIOD inclusions to a native rule, preserving its
	## existing inclusions, COUNT/UNTIL and source exclusions. Native inclusion
	## capacity also bounds the combined inputs before deduplication. Repeated
	## equal definitions coalesce; conflicting endings at one source fail even
	## when excluded or outside the query. This profile never picks a winner.
	## The context explicitly assigns meaning to the native rule's source labels
	## and window. All periods must match that UTC/local form. Local rules are
	## supplied immutable data, not a TZID lookup. Both starts and local ends use
	## first-fold/before-gap RFC policies. UTC uses fixed zero-offset POSIX rules
	## on [I64.lowest, I64.highest), without leap-second positions. Native rule
	## ranges remain native ranges; the text parser limits only supplied periods.
	## No recurrence or zone work is done here;
	## the returned TimedSchedule uses its ordinary budgets and resumptions.
	## Construction is O(n log n), with bounded input buffers; not a full RRULE
	## parser or an ICS property adapter. Existing duration overrides must be
	## supplied together as periods rather than merged from another schedule.
	schedule : id, TimedRecurrence, TimedRecurrence.Window, ICalDuration, List(ICalPeriod), Context -> Try(TimedSchedule(id), [TooManyPeriods, IncompatibleContext, TooManySelectors, InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	schedule = |series, rule, window, duration, periods, context| {
		prepared = prepare(rule, duration, periods, context)?
		TimedSchedule.from_prepared(series, prepared.rule, window, prepared.endings, prepared.context)
	}

	## Advanced preparation without a query window or occurrence enumeration.
	## Returns checked TimedSchedule.Endings for reuse with from_prepared.
	## The calling wrapper retains original PERIOD declarations for export;
	## this execution record alone is not a standard storage representation.
	prepare : TimedRecurrence, ICalDuration, List(ICalPeriod), Context -> Try({ rule : TimedRecurrence, endings : TimedSchedule.Endings, context : TimedRecurrence.Context }, [TooManyPeriods, IncompatibleContext, TooManySelectors, InvalidDuration, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	prepare = |rule, duration, periods, context| {
		if periods.len() > 4096 {
			return Err(TooManyPeriods)
		}
		var $starts = []
		var $overrides = []
		for period in periods {
			compatible = match context {
				Utc => ICalDateTime.form(period.start) == Utc
				Local(_) => ICalDateTime.form(period.start) == Local
			}
			if !compatible {
				return Err(IncompatibleContext)
			}
			$starts = $starts.append(ICalDateTime.source(period.start))
			native_ending = match period.ending {
				Duration(value) => After(ICalDuration.to_duration(value))
				End(value) => match context {
					Utc => {
						boundary = match ICalDateTime.utc_boundary(value) {
							Ok(resolved) => resolved
							Err(OutOfRange) => return Err(OutOfRange)
							Err(NeedsContext) => crash "validated matching UTC period endpoints"
						}
						AtBoundary(boundary)
					}
					Local(_) => AtLocal({ source: ICalDateTime.local_label(value), occurrence: First, gap: UseOffsetBeforeGap })
				}
			}
			$overrides = $overrides.append({ source: ICalDateTime.local_label(period.start), ending: native_ending })
		}
		combined = TimedRecurrence.add_inclusions(rule, $starts)?
		rules = match context {
			Local(value) => value
			Utc => utc_rules(I64.lowest, I64.highest)
		}
		endings = TimedSchedule.Endings.new(ICalDuration.to_duration(duration), $overrides)?
		Ok({ rule: combined, endings, context: { rules, occurrence: First, gap: UseOffsetBeforeGap } })
	}
}

# Explicit UTC context: a fixed POSIX profile, without leap-second positions.
# Constant valid constructors; no ambient rules or clock. The maximum I64
# boundary is an exclusive validity end, never a generated starting label.
utc_rules = |lower, upper| {
	validity = match PosixSpan.new(PosixBoundary.from_microseconds(lower), PosixBoundary.from_microseconds(upper)) {
		Ok(value) => value
		Err(_) => crash "ordered fixed UTC bounds"
	}
	match ZoneRules.new_bounded("UTC", "posix-fixed-v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 }) {
		Ok(value) => value
		Err(_) => crash "valid fixed UTC definition"
	}
}

expect ICalPeriod.parse("19970101T180000Z/19970101T180000Z") == Err(InvalidPeriod)
expect ICalPeriod.parse("19970101T180000Z/19960101T180000Z") == Err(InvalidPeriod)
expect ICalPeriod.parse("19970101T180000Z/19970102T070000") == Err(MixedForms)
expect ICalPeriod.parse("19970101T180000Z/PT0S") == Err(Duration(NonPositive))
expect ICalPeriod.parse("19970101T180000Z/-PT1H") == Err(Duration(NonPositive))
expect ICalPeriod.parse("19970101T180000Z/") == Err(End(Incomplete))
expect ICalPeriod.parse("19970101T180000Z/PT1H/PT2H") == Err(Malformed)
expect ICalPeriod.parse("X".repeat(274)) == Err(TooLarge)
expect ICalPeriod.to_text(ICalPeriod.parse("19970101t180000z/+pt5h30m")?) == "19970101T180000Z/PT19800S"

# One rule start and its duplicate PERIOD inclusion must emit one appointment.
# Finite resumes deliberately pause between start and end classification.
test_period_span = |text, context, steps| {
	period = match ICalPeriod.parse(text) {
		Ok(value) => value
		Err(error) => return Err(Parse(error))
	}
	source = ICalDateTime.source(ICalPeriod.start(period))
	end_date = Calendar.Arithmetic.shift_day(source.date, Calendar.Delta.days(1), Reject)?
	window = { start: ICalDateTime.local_label(ICalPeriod.start(period)), end: LocalDateTime.new(Calendar.Date.from_gregorian(end_date), source.clock) }
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	var $cursor = ICalPeriod.schedule(42.U64, rule, window, test_duration("PT1H"), [period, period], context)?
	var $spans = []
	var $calls = 0.U64
	while $calls < 100 {
		batch = match TimedSchedule.collect($cursor, { work: { max_steps: 1, max_buffered: 2, max_zone_segments: steps, max_zone_candidates: 2 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(error) => return Err(Execution(error))
		}
		for occurrence in batch.occurrences {
			$spans = $spans.append(TimedOccurrence.span(occurrence))
		}
		match batch.status {
			Complete => return Ok($spans)
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	Err(FixtureDidNotTerminate)
}

# Sourced examples: RFC 5545 (September 2009) section 3.3.9.
# https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.9
# 18:00 to next-day 07:00 is 13 hours; the second example is 5h30m.
expect {
	var $valid = Bool.True
	for case in [{ text: "19970101T180000Z/19970102T070000Z", seconds: 46800.I64 }, { text: "19970101T180000Z/PT5H30M", seconds: 19800 }] {
		spans = test_period_span(case.text, Utc, 1)?
		$valid = $valid and spans.len() == 1 and PosixSpan.coordinate_width(spans.get(0)?) == Ok(PosixDelta.from_microseconds(case.seconds * 1000000))
	}
	$valid
}

test_new_york = |spring| {
	lower = if spring {
		"20070310T000000Z"
	} else {
		"20071103T000000Z"
	}
	upper = if spring {
		"20070313T000000Z"
	} else {
		"20071106T000000Z"
	}
	transition = if spring {
		"20070311T070000Z"
	} else {
		"20071104T060000Z"
	}
	validity = PosixSpan.new(ICalDateTime.utc_boundary(test_timestamp(lower))?, ICalDateTime.utc_boundary(test_timestamp(upper))?)?
	at = ICalDateTime.utc_boundary(test_timestamp(transition))?
	ZoneRules.new_bounded(
		"RFC5545/New_York",
		"2007-examples",
		validity,
		FixedOffset.from_seconds(
			if spring {
				-18000
			} else {
				-14400
			},
		),
		[
			{
				at,
				offset: FixedOffset.from_seconds(
					if spring {
						-14400
					} else {
						-18000
					},
				),
			},
		],
		{ minimum: -18000, maximum: -14400 },
	)
}

# RFC 5545 section 3.3.5 supplies the 2007 New York gap and fold meanings.
# The period endpoints extend those source facts using direct offset arithmetic.
expect {
	rules = test_new_york(Bool.True)?
	spans = test_period_span("20070311T023000/20070311T040000", Local(rules), 1)?
	span = spans.get(0)?
	spans.len() == 1 and PosixSpan.coordinate_width(span) == Ok(PosixDelta.from_microseconds(1800000000)) and PosixSpan.start(span) == ICalDateTime.utc_boundary(ICalDateTime.parse("20070311T073000Z")?)?
}
expect {
	rules = test_new_york(Bool.False)?
	spans = test_period_span("20071104T013000/20071104T020000", Local(rules), 1)?
	spans.len() == 1 and PosixSpan.coordinate_width(spans.get(0)?) == Ok(PosixDelta.from_microseconds(5400000000))
}
expect {
	# Increasing labels collapse: both endpoints mean 07:30Z under RFC policy.
	rules = test_new_york(Bool.True)?
	match test_period_span("20070311T023000/20070311T033000", Local(rules), 1) {
		Err(Execution(InvalidDuration)) => Bool.True
		_ => Bool.False
	}
}
expect {
	match test_period_span("19970101T180000/PT1H", Utc, 1) {
		Err(IncompatibleContext) => Bool.True
		_ => Bool.False
	}
}

test_timestamp = |text| match ICalDateTime.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture timestamp"
}

test_duration = |text| match ICalDuration.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture duration"
}

expect {
	# Gap adjustment maps 02:30 and 03:30 to the same boundary. They remain
	# distinct source occurrences with different ending definitions.
	rules = test_new_york(Bool.True)?
	first = test_period("20070311T023000/PT1H")
	second = test_period("20070311T033000/PT2H")
	source = ICalDateTime.source(ICalPeriod.start(first))
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	window = { start: ICalDateTime.local_label(ICalPeriod.start(first)), end: ICalDateTime.local_label(test_timestamp("20070312T000000")) }
	default_duration = test_duration("PT1H")
	cursor = ICalPeriod.schedule({}, rule, window, default_duration, [first, second], Local(rules))?
	result = TimedSchedule.collect(cursor, { work: { max_steps: 100, max_buffered: 2, max_zone_segments: 20, max_zone_candidates: 2 }, max_occurrences: 3 })?
	a = result.occurrences.get(0)?
	b = result.occurrences.get(1)?
	span_a = TimedOccurrence.span(a)
	span_b = TimedOccurrence.span(b)
	valid = result.occurrences.len() == 2 and PosixSpan.start(span_a) == PosixSpan.start(span_b) and TimedOccurrence.id(a).source != TimedOccurrence.id(b).source and PosixSpan.coordinate_width(span_a) == Ok(PosixDelta.from_microseconds(3600000000)) and PosixSpan.coordinate_width(span_b) == Ok(PosixDelta.from_microseconds(7200000000))
	# Excluding the original gap label must not exclude the other source.
	excluded = TimedRecurrence.with_exclusions(rule, [ICalDateTime.local_label(ICalPeriod.start(first))])?
	only_second = ICalPeriod.schedule({}, excluded, window, default_duration, [first, second], Local(rules))?
	remaining = TimedSchedule.collect(only_second, { work: { max_steps: 100, max_buffered: 2, max_zone_segments: 20, max_zone_candidates: 2 }, max_occurrences: 3 })?
	valid and remaining.occurrences.len() == 1 and TimedOccurrence.id(remaining.occurrences.get(0)?).source == TimedOccurrence.id(b).source
}

expect {
	first = test_period("19970101T180000Z/PT1H")
	conflicting = test_period("19970101T180000Z/19970101T190000Z")
	source = ICalDateTime.source(ICalPeriod.start(first))
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	window = { start: ICalDateTime.local_label(ICalPeriod.start(first)), end: ICalDateTime.local_label(test_timestamp("19970102T180000Z")) }
	conflict = match ICalPeriod.schedule({}, rule, window, test_duration("PT1H"), [first, conflicting], Utc) {
		Err(ConflictingEnding(_)) => Bool.True
		_ => Bool.False
	}
	large = match ICalPeriod.schedule({}, rule, window, test_duration("PT1H"), List.repeat(first, 4097), Utc) {
		Err(TooManyPeriods) => Bool.True
		_ => Bool.False
	}
	filled = TimedRecurrence.with_inclusions(rule, [source])?
	combined_large = match TimedRecurrence.add_inclusions(filled, List.repeat(source, 4096)) {
		Err(TooManySelectors) => Bool.True
		_ => Bool.False
	}
	conflict and large and combined_large
}

test_period = |text| match ICalPeriod.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture period"
}

expect {
	# Source ordering can differ from resolved ordering across offset changes;
	# these local declaration facts must not imply a validated POSIX span.
	local = ICalPeriod.parse("19970902T090000/19970902T080000")?
	start = ICalDateTime.local_label(ICalPeriod.start(local))
	end = ICalDateTime.local_label(ICalDateTime.parse("19970902T080000")?)
	huge = ICalPeriod.parse("19970902T090000Z/P9223372036854775807D")?
	ICalPeriod.fact_count(local) == 4 and ICalPeriod.fact_count(huge) == 3 and
		ICalPeriod.fact_at(local, 0) == Item(SemanticFact.new(ICalPeriodDescription({ form: Local, start, ending: Endpoint(end) }))) and
			ICalPeriod.fact_at(local, 1) == Item(SemanticFact.new(ICalDateTimeDescription({ role: Start, local: start, form: Local }))) and
				ICalPeriod.fact_at(local, 2) == Item(SemanticFact.new(ICalDateTimeDescription({ role: End, local: end, form: Local }))) and
					ICalPeriod.fact_at(local, 3) == Item(SemanticFact.new(Requirement(ZoneContext))) and
						ICalPeriod.fact_at(huge, 0) == Item(SemanticFact.new(ICalPeriodDescription({ form: Utc, start, ending: Duration({ days: I64.highest, seconds: 0 }) }))) and
							ICalPeriod.fact_at(huge, 2) == Item(SemanticFact.new(ICalDurationDescription({ role: PeriodEnding, days: I64.highest, seconds: 0 }))) and
								ICalPeriod.fact_at(huge, 3) == End and ICalPeriod.fact_at(local, 4) == End and
									ICalPeriod.fact_at(huge, U64.highest) == End and ICalPeriod.to_inspect(huge).count_utf8_bytes() <= 256
}
