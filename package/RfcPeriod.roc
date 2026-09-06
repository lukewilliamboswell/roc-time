import GregorianDate
import CalendarDate
import CalendarArithmetic
import CalendarDelta
import CalendarPattern
import ClockTime
import PosixDelta
import RfcDateTime
import RfcDuration
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
## values share RfcDateTime's year, precision and leap-second profile. Both
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
## import time.RfcPeriod
## expect {
##     value = RfcPeriod.parse("19970101T180000Z/PT5H30M")?
##     RfcPeriod.to_text(value) == "19970101T180000Z/PT19800S"
## }
## ```
RfcPeriod :: { start : RfcDateTime, ending : Ending }.{
	Ending : [End(RfcDateTime), Duration(RfcDuration)]
	Context : [Utc, Local(ZoneRules)]
	Error : [Malformed, TooLarge, Start(RfcDateTime.Error), End(RfcDateTime.Error), Duration(RfcDuration.Error), MixedForms, InvalidPeriod]

	## Generic encodings carry canonical text, never the opaque backing record.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : RfcPeriod, rest : state }, [InvalidRfcPeriod(Error), Encoding(err), ..]))
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
				Err(error) => Err(InvalidRfcPeriod(error))
			}
		}
	}

	encoder_for : encoding -> (RfcPeriod, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(RfcPeriod, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid RfcPeriod literal: ${Str.inspect(error)}"))
	}

	profile : Str
	profile = "rfc5545-period-values-v1"
	parse : Str -> Try(RfcPeriod, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 273 {
			return Err(TooLarge)
		}
		(left, right) = match text.split_on("/") {
			[a, b] => (a, b)
			_ => return Err(Malformed)
		}
		start = match RfcDateTime.parse(left) {
			Ok(value) => value
			Err(error) => return Err(Start(error))
		}
		first = right.to_utf8().get(0) ?? 0
		ending = if first == 80 or first == 112 or first == 43 or first == 45 {
			parsed_duration = match RfcDuration.parse(right) {
				Ok(value) => value
				Err(error) => return Err(Duration(error))
			}
			Duration(parsed_duration)
		} else {
			end = match RfcDateTime.parse(right) {
				Ok(value) => value
				Err(error) => return Err(End(error))
			}
			if RfcDateTime.form(start) != RfcDateTime.form(end) {
				return Err(MixedForms)
			}
			if RfcDateTime.form(start) == Utc and LocalDateTime.compare_position(RfcDateTime.local_label(start), RfcDateTime.local_label(end)) != LT {
				return Err(InvalidPeriod)
			}
			End(end)
		}
		Ok({ start, ending })
	}
	start : RfcPeriod -> RfcDateTime
	start = |value| value.start
	ending : RfcPeriod -> Ending
	ending = |value| value.ending
	to_text : RfcPeriod -> Str
	to_text = |value| {
		end_text = match value.ending {
			End(end) => RfcDateTime.to_text(end)
			Duration(duration) => RfcDuration.to_text(duration)
		}
		"${RfcDateTime.to_text(value.start)}/${end_text}"
	}
	is_eq : RfcPeriod, RfcPeriod -> Bool
	is_eq = |a, b| a.start == b.start and a.ending == b.ending
	to_hash : RfcPeriod, Hasher -> Hasher
	to_hash = |value, hasher| {
		base = value.start.to_hash(hasher)
		match value.ending {
			End(end) => end.to_hash((0.U8).to_hash(base))
			Duration(duration) => duration.to_hash((1.U8).to_hash(base))
		}
	}
	to_inspect : RfcPeriod -> Str
	to_inspect = |value| "RfcPeriod(${to_text(value)})"

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
	schedule : id, TimedRecurrence, TimedRecurrence.Window, RfcDuration, List(RfcPeriod), Context -> Try(TimedSchedule(id), [TooManyPeriods, IncompatibleContext, TooManySelectors, InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	schedule = |series, rule, window, duration, periods, context| {
		if periods.len() > 4096 {
			return Err(TooManyPeriods)
		}
		var starts = []
		var overrides = []
		for period in periods {
			compatible = match context {
				Utc => RfcDateTime.form(period.start) == Utc
				Local(_) => RfcDateTime.form(period.start) == Local
			}
			if !compatible {
				return Err(IncompatibleContext)
			}
			starts = starts.append(RfcDateTime.source(period.start))
			native_ending = match period.ending {
				Duration(value) => After(RfcDuration.to_duration(value))
				End(value) => match context {
					Utc => {
						boundary = match RfcDateTime.utc_boundary(value) {
							Ok(resolved) => resolved
							Err(OutOfRange) => return Err(OutOfRange)
							Err(NeedsContext) => crash "validated matching UTC period endpoints"
						}
						AtBoundary(boundary)
					}
					Local(_) => AtLocal({ source: RfcDateTime.local_label(value), occurrence: First, gap: UseOffsetBeforeGap })
				}
			}
			overrides = overrides.append({ source: RfcDateTime.local_label(period.start), ending: native_ending })
		}
		combined = TimedRecurrence.add_inclusions(rule, starts)?
		rules = match context {
			Local(value) => value
			Utc => utc_rules(I64.lowest, I64.highest)
		}
		TimedSchedule.new_with_endings(series, combined, window, RfcDuration.to_duration(duration), overrides, { rules, occurrence: First, gap: UseOffsetBeforeGap })
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

expect RfcPeriod.parse("19970101T180000Z/19970101T180000Z") == Err(InvalidPeriod)
expect RfcPeriod.parse("19970101T180000Z/19960101T180000Z") == Err(InvalidPeriod)
expect RfcPeriod.parse("19970101T180000Z/19970102T070000") == Err(MixedForms)
expect RfcPeriod.parse("19970101T180000Z/PT0S") == Err(Duration(NonPositive))
expect RfcPeriod.parse("19970101T180000Z/-PT1H") == Err(Duration(NonPositive))
expect RfcPeriod.parse("19970101T180000Z/") == Err(End(Incomplete))
expect RfcPeriod.parse("19970101T180000Z/PT1H/PT2H") == Err(Malformed)
expect RfcPeriod.parse("X".repeat(274)) == Err(TooLarge)
expect RfcPeriod.to_text(RfcPeriod.parse("19970101t180000z/+pt5h30m")?) == "19970101T180000Z/PT19800S"

# One rule start and its duplicate PERIOD inclusion must emit one appointment.
# Finite resumes deliberately pause between start and end classification.
test_period_span = |text, context, steps| {
	period = match RfcPeriod.parse(text) {
		Ok(value) => value
		Err(error) => return Err(Parse(error))
	}
	source = RfcDateTime.source(RfcPeriod.start(period))
	end_date = CalendarArithmetic.shift_day(source.date, CalendarDelta.days(1), Reject)?
	window = { start: RfcDateTime.local_label(RfcPeriod.start(period)), end: LocalDateTime.new(CalendarDate.from_gregorian(end_date), source.clock) }
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	var cursor = RfcPeriod.schedule(42.U64, rule, window, test_duration("PT1H"), [period, period], context)?
	var spans = []
	var calls = 0.U64
	while calls < 100 {
		batch = match TimedSchedule.collect(cursor, { work: { max_steps: 1, max_buffered: 2, max_zone_segments: steps, max_zone_candidates: 2 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(error) => return Err(Execution(error))
		}
		for occurrence in batch.occurrences {
			spans = spans.append(TimedOccurrence.span(occurrence))
		}
		match batch.status {
			Complete => return Ok(spans)
			Limited(progress) => {
				cursor = progress.cursor
			}
		}
		calls = calls + 1
	}
	Err(FixtureDidNotTerminate)
}

# Sourced examples: RFC 5545 (September 2009) section 3.3.9.
# https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.9
# 18:00 to next-day 07:00 is 13 hours; the second example is 5h30m.
expect {
	var valid = Bool.True
	for case in [{ text: "19970101T180000Z/19970102T070000Z", seconds: 46800.I64 }, { text: "19970101T180000Z/PT5H30M", seconds: 19800 }] {
		spans = test_period_span(case.text, Utc, 1)?
		valid = valid and spans.len() == 1 and PosixSpan.coordinate_width(spans.get(0)?) == Ok(PosixDelta.from_microseconds(case.seconds * 1000000))
	}
	valid
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
	validity = PosixSpan.new(RfcDateTime.utc_boundary(test_timestamp(lower))?, RfcDateTime.utc_boundary(test_timestamp(upper))?)?
	at = RfcDateTime.utc_boundary(test_timestamp(transition))?
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
	spans.len() == 1 and PosixSpan.coordinate_width(span) == Ok(PosixDelta.from_microseconds(1800000000)) and PosixSpan.start(span) == RfcDateTime.utc_boundary(RfcDateTime.parse("20070311T073000Z")?)?
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

test_timestamp = |text| match RfcDateTime.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture timestamp"
}

test_duration = |text| match RfcDuration.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture duration"
}

expect {
	# Gap adjustment maps 02:30 and 03:30 to the same boundary. They remain
	# distinct source occurrences with different ending definitions.
	rules = test_new_york(Bool.True)?
	first = test_period("20070311T023000/PT1H")
	second = test_period("20070311T033000/PT2H")
	source = RfcDateTime.source(RfcPeriod.start(first))
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	window = { start: RfcDateTime.local_label(RfcPeriod.start(first)), end: RfcDateTime.local_label(test_timestamp("20070312T000000")) }
	default_duration = test_duration("PT1H")
	cursor = RfcPeriod.schedule({}, rule, window, default_duration, [first, second], Local(rules))?
	result = TimedSchedule.collect(cursor, { work: { max_steps: 100, max_buffered: 2, max_zone_segments: 20, max_zone_candidates: 2 }, max_occurrences: 3 })?
	a = result.occurrences.get(0)?
	b = result.occurrences.get(1)?
	span_a = TimedOccurrence.span(a)
	span_b = TimedOccurrence.span(b)
	valid = result.occurrences.len() == 2 and PosixSpan.start(span_a) == PosixSpan.start(span_b) and TimedOccurrence.id(a).source != TimedOccurrence.id(b).source and PosixSpan.coordinate_width(span_a) == Ok(PosixDelta.from_microseconds(3600000000)) and PosixSpan.coordinate_width(span_b) == Ok(PosixDelta.from_microseconds(7200000000))
	# Excluding the original gap label must not exclude the other source.
	excluded = TimedRecurrence.with_exclusions(rule, [RfcDateTime.local_label(RfcPeriod.start(first))])?
	only_second = RfcPeriod.schedule({}, excluded, window, default_duration, [first, second], Local(rules))?
	remaining = TimedSchedule.collect(only_second, { work: { max_steps: 100, max_buffered: 2, max_zone_segments: 20, max_zone_candidates: 2 }, max_occurrences: 3 })?
	valid and remaining.occurrences.len() == 1 and TimedOccurrence.id(remaining.occurrences.get(0)?).source == TimedOccurrence.id(b).source
}

expect {
	first = test_period("19970101T180000Z/PT1H")
	conflicting = test_period("19970101T180000Z/19970101T190000Z")
	source = RfcDateTime.source(RfcPeriod.start(first))
	rule = TimedRecurrence.new(source, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	window = { start: RfcDateTime.local_label(RfcPeriod.start(first)), end: RfcDateTime.local_label(test_timestamp("19970102T180000Z")) }
	conflict = match RfcPeriod.schedule({}, rule, window, test_duration("PT1H"), [first, conflicting], Utc) {
		Err(ConflictingEnding(_)) => Bool.True
		_ => Bool.False
	}
	large = match RfcPeriod.schedule({}, rule, window, test_duration("PT1H"), List.repeat(first, 4097), Utc) {
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

test_period = |text| match RfcPeriod.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid fixture period"
}
