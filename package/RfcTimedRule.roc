import SemanticFact
import TimedOccurrence
import PosixSpan
import PosixDelta
import ZoneRules
import FixedOffset
import CalendarDate
import ClockTime
import RfcRuleParts
import RfcDateTime
import RfcDuration
import RfcPeriod
import TimedRecurrence
import TimedSchedule
import LocalDateTime

## Extracted RFC 5545 timed recurrence values, profile timed-values-v1.
## UTC, floating and zoned DTSTART modes are explicit. UTC starts require Z;
## floating/zoned starts require local labels. UNTIL must be local for floating
## starts and UTC for UTC/zoned starts. Native UntilBoundary handles UTC cutoffs.
##
## Frequencies SECONDLY through YEARLY and supported native selectors share the
## DATE adapter's RRULE grammar. Disputed omitted YEARLY defaults remain explicit
## unsupported cases. BYSECOND=60 remains unsupported on the POSIX profile.
## RDATE/EXDATE entries are extracted values and may contain comma lists. PERIOD
## entries use RfcPeriod. All inclusions/exclusions must match DTSTART's form;
## mixed UTC/local exception matching is explicitly unsupported. Zoned values
## assume one property TZID mapped by the caller to the supplied immutable rules.
## This does not parse content lines, folded ICS, property parameters or TZIDs.
##
## Input is limited to 65536 bytes in total, 4096 entries in each input list,
## and 4096 expanded values per kind. Native combined inclusion capacity also
## applies when PERIOD values are added. Parsing constructs native definitions
## without enumerating occurrences or consulting rules. Source spelling and
## versioned persistence are outside this profile.
RfcTimedRule :: { rule : TimedRecurrence, duration : RfcDuration, periods : List(RfcPeriod), mode : Mode }.{
	Mode : [Utc, Floating, Zoned]
	Parts : { start : Str, rule : Str, duration : Str, inclusions : List(Str), exclusions : List(Str), periods : List(Str), mode : Mode }
	Error : [TooLarge, DateTime(Str, RfcDateTime.Error), Duration(RfcDuration.Error), Period(RfcPeriod.Error), Rule(RfcRuleParts.Error), Incompatible(Str), Unsupported(Str), InvalidRule([InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart])]
	profile : Str
	profile = "rfc5545-timed-values-v1"
	parse : Parts -> Try(RfcTimedRule, Error)
	parse = |parts| {
		if parts.inclusions.len() > 4096 or parts.exclusions.len() > 4096 or parts.periods.len() > 4096 {
			return Err(TooLarge)
		}
		var remaining = 65536.U64
		for text in [parts.start, parts.rule, parts.duration].concat(parts.inclusions).concat(parts.exclusions).concat(parts.periods) {
			if text.count_utf8_bytes() > remaining {
				return Err(TooLarge)
			}
			remaining = remaining - text.count_utf8_bytes()
		}
		start = timestamp(parts.start, "DTSTART")?
		expected_form = match parts.mode {
			Utc => Utc
			_ => Local
		}
		if RfcDateTime.form(start) != expected_form {
			return Err(Incompatible("DTSTART form and mode"))
		}
		duration = match RfcDuration.parse(parts.duration) {
			Ok(value) => value
			Err(error) => return Err(Duration(error))
		}
		fields = match RfcRuleParts.parse(parts.rule, Timed) {
			Ok(value) => value
			Err(error) => return Err(Rule(error))
		}
		termination = match fields.termination {
			Forever => Forever
			Count(count) => Count(count)
			Until(text) => {
				end = timestamp(text, "UNTIL")?
				match parts.mode {
					Floating => {
						if RfcDateTime.form(end) != Local {
							return Err(Incompatible("floating DTSTART requires local UNTIL"))
						}
						Until(RfcDateTime.local_label(end))
					}
					Utc | Zoned => {
						if RfcDateTime.form(end) != Utc {
							return Err(Incompatible("UTC or zoned DTSTART requires UTC UNTIL"))
						}
						boundary = match RfcDateTime.utc_boundary(end) {
							Ok(value) => value
							Err(_) => crash "validated UTC timestamp within year profile"
						}
						UntilBoundary(boundary)
					}
				}
			}
		}
		constructed = match fields.subdaily {
			None => TimedRecurrence.new(RfcDateTime.source(start), { calendar: fields.pattern, clocks: fields.clocks, termination, by_set_pos: fields.positions })
			Some(frequency) => TimedRecurrence.new_subdaily(RfcDateTime.source(start), { pattern: { frequency, interval: fields.pattern.interval, calendar: { by_month: fields.pattern.by_month, by_month_day: fields.pattern.by_month_day, by_year_day: fields.pattern.by_year_day, by_day: fields.pattern.by_day.map(|day| day.weekday) }, clocks: fields.clocks }, termination, by_set_pos: fields.positions })
		}
		rule = match constructed {
			Ok(value) => value
			Err(error) => return Err(InvalidRule(error))
		}
		inclusions = timestamps(parts.inclusions, "RDATE", expected_form)?
		exclusions = timestamps(parts.exclusions, "EXDATE", expected_form)?
		included = match TimedRecurrence.with_inclusions(rule, inclusions.map(RfcDateTime.source)) {
			Ok(value) => value
			Err(_) => return Err(TooLarge)
		}
		filtered = match TimedRecurrence.with_exclusions(included, exclusions.map(RfcDateTime.local_label)) {
			Ok(value) => value
			Err(_) => return Err(TooLarge)
		}
		var periods = []
		for entry in parts.periods {
			for text in entry.split_on(",") {
				if periods.len() == 4096 {
					return Err(TooLarge)
				}
				period = match RfcPeriod.parse(text) {
					Ok(value) => value
					Err(error) => return Err(Period(error))
				}
				if RfcDateTime.form(RfcPeriod.start(period)) != expected_form {
					return Err(Unsupported("mixed PERIOD and DTSTART forms"))
				}
				periods = periods.append(period)
			}
		}
		Ok({ rule: filtered, duration, periods, mode: parts.mode })
	}

	## Explicit context for the selected mode. Floating values are bound by the
	## application for this evaluation; no timezone is inferred. Rules remain
	## immutable in the native cursor. Start/end selection follows RFC first-fold
	## and before-gap policies, and all native schedule budgets remain available.
	schedule : id, RfcTimedRule, TimedRecurrence.Window, RfcPeriod.Context -> Try(TimedSchedule(id), [IncompatibleContext, TooManyPeriods, TooManySelectors, InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	schedule = |series, value, window, context| {
		compatible = match (value.mode, context) {
			(Utc, Utc) => Bool.True
			(Floating, Local(_)) | (Zoned, Local(_)) => Bool.True
			_ => Bool.False
		}
		if !compatible {
			return Err(IncompatibleContext)
		}
		RfcPeriod.schedule(series, value.rule, window, value.duration, value.periods, context)
	}

	## The wrapper retains RFC mode and policy, while native facts expose the
	## effective selectors after adapter defaults. No original RRULE spelling.
	fact_count : RfcTimedRule -> U64
	fact_count = |rule| 2 + rule.periods.len() + TimedRecurrence.fact_count(rule.rule)
	fact_at : RfcTimedRule, U64 -> [End, Item(SemanticFact)]
	fact_at = |rule, index| {
		if index >= fact_count(rule) {
			return End
		}
		if index == 0 {
			return Item(SemanticFact.new(RfcTimedRuleDescription({ mode: rule.mode, period_count: rule.periods.len() })))
		}
		if index == 1 {
			context = match rule.mode {
				Utc => FixedUtc
				Floating | Zoned => Required
			}
			return Item(SemanticFact.new(RecurrencePolicy({ context, occurrence: First, gap: UseOffsetBeforeGap })))
		}
		if index == 2 {
			components = RfcDuration.components(rule.duration)
			return Item(SemanticFact.new(RfcDurationDescription({ role: RecurrenceEnding, days: components.days, seconds: components.seconds })))
		}
		remaining = index - 3
		if remaining < rule.periods.len() {
			return match rule.periods.get(remaining) {
				Ok(period) => RfcPeriod.fact_at(period, 0)
				Err(_) => End
			}
		}
		native_index = remaining - rule.periods.len()
		# Replace native caller-supplied policy with the RFC wrapper policy.
		TimedRecurrence.fact_at(
			rule.rule,
			if native_index < 2 {
				native_index
			} else {
				native_index + 1
			},
		)
	}
	to_inspect : RfcTimedRule -> Str
	to_inspect = |value| {
		summary = match fact_at(value, 0) {
			Item(fact) => SemanticFact.summary(fact)
			End => crash "RFC rule always has a summary"
		}
		ending = match TimedRecurrence.fact_at(value.rule, 1) {
			Item(fact) => SemanticFact.summary(fact)
			End => crash "Native rule always has termination"
		}
		"${summary} ${ending}"
	}
}

timestamp : Str, Str -> Try(RfcDateTime, RfcTimedRule.Error)
timestamp = |text, part| match RfcDateTime.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(DateTime(part, error))
}

timestamps : List(Str), Str, RfcDateTime.Form -> Try(List(RfcDateTime), RfcTimedRule.Error)
timestamps = |entries, part, form| {
	var values = []
	for entry in entries {
		for text in entry.split_on(",") {
			if values.len() == 4096 {
				return Err(TooLarge)
			}
			value = timestamp(text, part)?
			if RfcDateTime.form(value) != form {
				return Err(Unsupported("mixed ${part} and DTSTART forms"))
			}
			values = values.append(value)
		}
	}
	Ok(values)
}

test_parts = |start, rule, mode| { start, rule, mode, duration: "P1D", inclusions: [], exclusions: [], periods: [] }

test_timestamp = |text| match RfcDateTime.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid timed-rule fixture timestamp"
}

test_observe = |parts, context, lower, upper| {
	parsed = match RfcTimedRule.parse(parts) {
		Ok(value) => value
		Err(error) => return Err(Parse(error))
	}
	window = { start: RfcDateTime.local_label(test_timestamp(lower)), end: RfcDateTime.local_label(test_timestamp(upper)) }
	var cursor = RfcTimedRule.schedule(42.U64, parsed, window, context)?
	var occurrences = []
	var calls = 0.U64
	while calls < 2000 {
		batch = match TimedSchedule.collect(cursor, { work: { max_steps: 3, max_buffered: 32, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(error) => return Err(Execution(error))
		}
		occurrences = occurrences.concat(batch.occurrences)
		match batch.status {
			Complete => return Ok(occurrences)
			Limited(progress) => {
				cursor = progress.cursor
			}
		}
		calls = calls + 1
	}
	Err(FixtureDidNotTerminate)
}

# RFC COUNT is anchored before query restriction and exclusions. Invalid
# February/April 31st candidates do not consume it. PERIOD overrides May 31.
expect {
	parts = { ..test_parts("20250131T090000Z", "FREQ=MONTHLY;COUNT=3", Utc), exclusions: ["20250331T090000Z"], inclusions: ["20250415T090000Z,20250415T090000Z"], periods: ["20250531T090000Z/PT2H"] }
	values = test_observe(parts, Utc, "20250301T000000Z", "20250801T000000Z")?
	months = values.map(|value| CalendarDate.to_fields(LocalDateTime.date(TimedRecurrence.Occurrence.source(TimedOccurrence.start(value)))).month)
	widths = values.map(|value| PosixSpan.coordinate_width(TimedOccurrence.span(value)))
	months == [4.U8, 5] and widths == [Ok(PosixDelta.from_microseconds(86400000000)), Ok(PosixDelta.from_microseconds(7200000000))]
}

# RFC 5545 section 3.8.5.3 and verified erratum 3883 (2014-02-14).
# https://www.rfc-editor.org/errata/eid3883
# The September 1997 New York fixture is UTC-04:00 throughout this window.
expect {
	validity = PosixSpan.new(RfcDateTime.utc_boundary(test_timestamp("19970901T000000Z"))?, RfcDateTime.utc_boundary(test_timestamp("19970904T000000Z"))?)?
	rules = ZoneRules.new_bounded("RFC5545/New_York", "1997-example", validity, FixedOffset.from_seconds(-14400), [], { minimum: -14400, maximum: -14400 })?
	var valid = Bool.True
	for case in [{ until: "19970902T210000Z", expected: [9.U8, 12, 15] }, { until: "19970902T170000Z", expected: [9, 12] }, { until: "19970902T190000Z", expected: [9, 12, 15] }] {
		parts = { ..test_parts("19970902T090000", "FREQ=HOURLY;INTERVAL=3;UNTIL=${case.until}", Zoned), duration: "PT1H" }
		values = test_observe(parts, Local(rules), "19970902T000000", "19970903T000000")?
		valid = valid and values.map(|value| ClockTime.to_fields(LocalDateTime.clock(TimedRecurrence.Occurrence.source(TimedOccurrence.start(value)))).hour) == case.expected
	}
	valid
}

expect {
	var valid = Bool.True
	for parts in [test_parts("20250101T090000Z", "FREQ=DAILY;UNTIL=20250102T090000", Utc), test_parts("20250101T090000", "FREQ=DAILY;UNTIL=20250102T090000Z", Floating), test_parts("20250101T090000", "FREQ=DAILY;UNTIL=20250102T090000", Zoned), test_parts("20250101T090000Z", "FREQ=DAILY", Zoned)] {
		valid = valid and match RfcTimedRule.parse(parts) {
			Err(Incompatible(_)) => Bool.True
			_ => Bool.False
		}
	}
	valid
}
expect {
	parts = { ..test_parts("20070311T023000", "FREQ=HOURLY;COUNT=2", Zoned), exclusions: ["20070311T073000Z"] }
	match RfcTimedRule.parse(parts) {
		Err(Unsupported("mixed EXDATE and DTSTART forms")) => Bool.True
		_ => Bool.False
	}
}
expect {
	parts = test_parts("20250101T090000Z", "FREQ=DAILY;BYSECOND=60", Utc)
	match RfcTimedRule.parse(parts) {
		Err(InvalidRule(UnsupportedLeapSecond)) => Bool.True
		_ => Bool.False
	}
}
expect {
	parts = test_parts("20250101T090000Z", "FREQ=DAILY;COUNT=1;COUNT=2", Utc)
	match RfcTimedRule.parse(parts) {
		Err(Rule(Duplicate("COUNT"))) => Bool.True
		_ => Bool.False
	}
}

expect {
	rule = RfcTimedRule.parse({ start: "20250101T090000", rule: "FREQ=DAILY;COUNT=1", duration: "P1D", inclusions: [], exclusions: ["20250101T090000"], periods: [], mode: Zoned })?
	# Exclusion preserves the one-count declaration; no occurrence is generated
	# merely to explain it. Wrapper mode supplies RFC gap/fold policy.
	RfcTimedRule.fact_at(rule, 0) == Item(SemanticFact.new(RfcTimedRuleDescription({ mode: Zoned, period_count: 0 }))) and RfcTimedRule.fact_at(rule, 1) == Item(SemanticFact.new(RecurrencePolicy({ context: Required, occurrence: First, gap: UseOffsetBeforeGap }))) and RfcTimedRule.fact_at(rule, 2) == Item(SemanticFact.new(RfcDurationDescription({ role: RecurrenceEnding, days: 1, seconds: 0 }))) and RfcTimedRule.fact_at(rule, 4) == Item(SemanticFact.new(RecurrenceTermination(Count(1)))) and RfcTimedRule.fact_at(rule, RfcTimedRule.fact_count(rule)) == End and RfcTimedRule.fact_at(rule, U64.highest) == End and RfcTimedRule.to_inspect(rule).count_utf8_bytes() <= 256
}
