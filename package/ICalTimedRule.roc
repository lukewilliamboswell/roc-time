import SemanticFact
import TimedOccurrence
import PosixSpan
import PosixBoundary
import PosixDelta
import ZoneRules
import FixedOffset
import Calendar
import ClockTime
import ICalRuleParts
import ICalDateTime
import ICalDuration
import ICalPeriod
import TimedRecurrence
import TimedSchedule
import LocalDateTime
import GregorianDate
import CalendarPattern
import ICalRuleText

## Extracted RFC 5545 timed recurrence values, profile timed-values.
## UTC, floating and zoned DTSTART modes are explicit. UTC starts require Z;
## floating/zoned starts require local labels. UNTIL must be local for floating
## starts and UTC for UTC/zoned starts. Native UntilBoundary handles UTC cutoffs.
##
## Supports SECONDLY through YEARLY with the DATE adapter's RRULE selectors.
## Some YEARLY combinations require explicit BYMONTH or BYDAY; see ICalDateRule.
## BYSECOND=60 is unsupported on the POSIX profile.
## RDATE/EXDATE entries are extracted values and may contain comma lists. PERIOD
## entries use ICalPeriod. RDATE/PERIOD values must match DTSTART's form.
## UTC EXDATE values are accepted for zoned DTSTART. Local
## exclusions match source labels; UTC exclusions match selected boundaries,
## including every colliding source and explicit inclusion, after COUNT and
## BYSETPOS. Floating/UTC mixtures remain unsupported. Zoned values
## assume one property TZID mapped by the caller to the supplied immutable rules.
## This does not parse content lines, folded ICS, property parameters or TZIDs.
##
## Input is limited to 65536 bytes in total, 4096 entries in each input list,
## and 4096 expanded values per kind. Native combined inclusion capacity also
## applies when PERIOD values are added. Parsing constructs native definitions
## without enumerating occurrences or consulting rules. Source spelling and
## application storage envelopes are outside this profile.
ICalTimedRule :: { rule : TimedRecurrence, duration : ICalDuration, periods : List(ICalPeriod), mode : Mode }.{
	## Utc uses Z values; Floating uses local labels interpreted by the caller; Zoned uses local labels under one explicitly supplied zone.
	Mode : [Utc, Floating, Zoned]
	## Extracted DTSTART, RRULE, duration, RDATE, EXDATE and PERIOD text plus interpretation mode. Supply values rather than ICS content lines.
	Parts : { start : Str, rule : Str, duration : Str, inclusions : List(Str), exclusions : List(Str), periods : List(Str), mode : Mode }
	## Reports property-level syntax, unsupported combinations, precision/range/size limits and native recurrence validation failures.
	Error : [TooLarge, OutOfRange(Str), PrecisionLoss(Str), DateTime(Str, ICalDateTime.Error), Duration(ICalDuration.Error), Period(ICalPeriod.Error), Rule(ICalRuleParts.Error), Incompatible(Str), Unsupported(Str), InvalidRule([InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart])]
	## Editable semantic rule, default duration, ordered PERIOD additions and mode. Pass edits through new to check profile compatibility.
	Definition : { rule : TimedRecurrence, duration : ICalDuration, periods : List(ICalPeriod), mode : Mode }

	## Returns the editable rule declaration, keeping source exceptions separate
	## from PERIOD ending overrides. Use to_parts for standard interchange.
	definition : ICalTimedRule -> Definition
	definition = |value| { rule: value.rule, duration: value.duration, periods: value.periods, mode: value.mode }

	## Checked construction/editing for this extracted-property profile. Does not
	## resolve zones or enumerate occurrences. Conflicting PERIOD endings remain
	## visible and are rejected by schedule construction, never silently dropped.
	## Validates by canonical rendering, including the exact aggregate byte cap;
	## temporarily allocates that bounded output. Cost matches to_parts below.
	new : Definition -> Try(ICalTimedRule, Error)
	new = |spec| {
		value = { rule: spec.rule, duration: spec.duration, periods: spec.periods, mode: spec.mode }
		_ = to_parts(value)?
		Ok(value)
	}

	## Canonical extracted property values, capped at 65536 total UTF-8 bytes.
	## Effective clock fields are explicit, preserving subdaily limiting fields
	## and lower-field expansion. Cost depends only on definition size: bounded
	## selector sorting and output bytes, never clock products or occurrences.
	## Output retains PERIOD order and ending intent; source spelling is absent.
	## Order is FREQ, INTERVAL, termination, calendar selectors, BYHOUR,
	## BYMINUTE, BYSECOND, BYSETPOS, WKST. All three effective clock fields
	## are written, including inherited values or full subdaily filter ranges.
	to_parts : ICalTimedRule -> Try(Parts, Error)
	to_parts = |value| {
		if value.periods.len() > 4096 {
			return Err(TooLarge)
		}
		data = TimedRecurrence.definition(value.rule)
		form = match value.mode {
			Utc => Utc
			Floating | Zoned => Local
		}
		start = local_text(data.anchor, form, "DTSTART")?
		(pattern, subdaily) = match data.pattern {
			Calendar(calendar) => (calendar, None)
			Subdaily(part) => ({ ..CalendarPattern.defaults(Daily), interval: part.interval, by_month: part.calendar.by_month, by_month_day: part.calendar.by_month_day, by_year_day: part.calendar.by_year_day, by_day: part.calendar.by_day.map(|weekday| { weekday, ordinal: 0 }) }, Some(part.frequency))
		}
		termination = match data.termination {
			Forever => Forever
			Count(count) => Count(count)
			Until(local) => {
				if value.mode != Floating {
					return Err(Incompatible("UTC or zoned DTSTART requires UTC UNTIL"))
				}
				Until(local_text(local, Local, "UNTIL")?)
			}
			UntilBoundary(boundary) => {
				if value.mode == Floating {
					return Err(Incompatible("floating DTSTART requires local UNTIL"))
				}
				local = match FixedOffset.project(FixedOffset.from_seconds(0), boundary, Gregorian) {
					Ok(label) => label
					Err(_) => return Err(OutOfRange("UNTIL"))
				}
				Until(local_text(local, Utc, "UNTIL")?)
			}
		}
		rule = match ICalRuleText.render({ pattern, subdaily, clocks: data.clocks, termination, positions: data.by_set_pos }) {
			Ok(text) => text
			Err(OutOfRange(part)) => return Err(OutOfRange(part))
			Err(error) => return Err(Rule(error))
		}
		var $inclusions = []
		for local in data.inclusions {
			$inclusions = $inclusions.append(local_text(local, form, "RDATE")?)
		}
		var $exclusions = []
		for local in data.exclusions {
			$exclusions = $exclusions.append(local_text(local, form, "EXDATE")?)
		}
		if !data.boundary_exclusions.is_empty() and value.mode != Zoned {
			return Err(Unsupported("boundary exclusions require zoned DTSTART"))
		}
		for boundary in data.boundary_exclusions {
			local = match FixedOffset.project(FixedOffset.from_seconds(0), boundary, Gregorian) {
				Ok(label) => label
				Err(_) => return Err(OutOfRange("EXDATE"))
			}
			$exclusions = $exclusions.append(local_text(local, Utc, "EXDATE")?)
		}
		var $periods = []
		for period in value.periods {
			if ICalDateTime.form(ICalPeriod.start(period)) != form {
				return Err(Unsupported("mixed PERIOD and DTSTART forms"))
			}
			$periods = $periods.append(ICalPeriod.to_text(period))
		}
		parts = { start, rule, duration: ICalDuration.to_text(value.duration), inclusions: $inclusions, exclusions: $exclusions, periods: $periods, mode: value.mode }
		var $remaining = 65536.U64
		for text in [parts.start, parts.rule, parts.duration].concat(parts.inclusions).concat(parts.exclusions).concat(parts.periods) {
			if text.count_utf8_bytes() > $remaining {
				return Err(TooLarge)
			}
			$remaining = $remaining - text.count_utf8_bytes()
		}
		Ok(parts)
	}

	## Supported extracted RFC 5545 property-value profile.
	profile : Str
	profile = "rfc5545-timed-values"

	## Parses extracted timed recurrence values without enumerating occurrences or resolving zones. Validates mode/UNTIL compatibility and the supported profile limits.
	parse : Parts -> Try(ICalTimedRule, Error)
	parse = |parts| {
		if parts.inclusions.len() > 4096 or parts.exclusions.len() > 4096 or parts.periods.len() > 4096 {
			return Err(TooLarge)
		}
		var $remaining = 65536.U64
		for text in [parts.start, parts.rule, parts.duration].concat(parts.inclusions).concat(parts.exclusions).concat(parts.periods) {
			if text.count_utf8_bytes() > $remaining {
				return Err(TooLarge)
			}
			$remaining = $remaining - text.count_utf8_bytes()
		}
		start = timestamp(parts.start, "DTSTART")?
		expected_form = match parts.mode {
			Utc => Utc
			_ => Local
		}
		if ICalDateTime.form(start) != expected_form {
			return Err(Incompatible("DTSTART form and mode"))
		}
		duration = match ICalDuration.parse(parts.duration) {
			Ok(value) => value
			Err(error) => return Err(Duration(error))
		}
		fields = match ICalRuleParts.parse(parts.rule, Timed) {
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
						if ICalDateTime.form(end) != Local {
							return Err(Incompatible("floating DTSTART requires local UNTIL"))
						}
						Until(ICalDateTime.local_label(end))
					}
					Utc | Zoned => {
						if ICalDateTime.form(end) != Utc {
							return Err(Incompatible("UTC or zoned DTSTART requires UTC UNTIL"))
						}
						boundary = match ICalDateTime.utc_boundary(end) {
							Ok(value) => value
							Err(_) => crash "validated UTC timestamp within year profile"
						}
						UntilBoundary(boundary)
					}
				}
			}
		}
		constructed = match fields.subdaily {
			None => TimedRecurrence.new(ICalDateTime.source(start), { calendar: fields.pattern, clocks: fields.clocks, termination, by_set_pos: fields.positions })
			Some(frequency) => TimedRecurrence.new_subdaily(ICalDateTime.source(start), { pattern: { frequency, interval: fields.pattern.interval, calendar: { by_month: fields.pattern.by_month, by_month_day: fields.pattern.by_month_day, by_year_day: fields.pattern.by_year_day, by_day: fields.pattern.by_day.map(|day| day.weekday) }, clocks: fields.clocks }, termination, by_set_pos: fields.positions })
		}
		rule = match constructed {
			Ok(value) => value
			Err(error) => return Err(InvalidRule(error))
		}
		inclusions = timestamps(parts.inclusions, "RDATE", expected_form)?
		exclusions = exclusion_values(parts.exclusions, expected_form, parts.mode)?
		included = match TimedRecurrence.with_inclusions(rule, inclusions.map(ICalDateTime.source)) {
			Ok(value) => value
			Err(_) => return Err(TooLarge)
		}
		filtered = match TimedRecurrence.with_exclusions(included, exclusions.local.map(ICalDateTime.local_label)) {
			Ok(value) => value
			Err(_) => return Err(TooLarge)
		}
		boundary_filtered = match TimedRecurrence.with_boundary_exclusions(filtered, exclusions.boundaries) {
			Ok(value) => value
			Err(_) => return Err(TooLarge)
		}
		var $periods = []
		for entry in parts.periods {
			for text in entry.split_on(",") {
				if $periods.len() == 4096 {
					return Err(TooLarge)
				}
				period = match ICalPeriod.parse(text) {
					Ok(value) => value
					Err(error) => return Err(Period(error))
				}
				if ICalDateTime.form(ICalPeriod.start(period)) != expected_form {
					return Err(Unsupported("mixed PERIOD and DTSTART forms"))
				}
				$periods = $periods.append(period)
			}
		}
		Ok({ rule: boundary_filtered, duration, periods: $periods, mode: parts.mode })
	}

	## Explicit context for the selected mode. Floating values are bound by the
	## application for this evaluation; no timezone is inferred. Rules remain
	## immutable in the native cursor. Start/end selection follows RFC first-fold
	## and before-gap policies, and all native schedule budgets remain available.
	schedule : id, ICalTimedRule, TimedRecurrence.Window, ICalPeriod.Context -> Try(TimedSchedule(id), [IncompatibleContext, TooManyPeriods, TooManySelectors, InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	schedule = |series, value, window, context| {
		prepared = prepare(value, context)?
		TimedSchedule.from_prepared(series, prepared.rule, window, prepared.endings, prepared.context)
	}

	## Advanced context validation and checked ending preparation, without
	## occurrence enumeration. Reuse with TimedSchedule.from_prepared; ordinary
	## callers can use ScheduleDefinition to retain the original declaration too.
	prepare : ICalTimedRule, ICalPeriod.Context -> Try({ rule : TimedRecurrence, endings : TimedSchedule.Endings, context : TimedRecurrence.Context }, [IncompatibleContext, TooManyPeriods, TooManySelectors, InvalidDuration, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	prepare = |value, context| {
		compatible = match (value.mode, context) {
			(Utc, Utc) => Bool.True
			(Floating, Local(_)) | (Zoned, Local(_)) => Bool.True
			_ => Bool.False
		}
		if !compatible {
			return Err(IncompatibleContext)
		}
		ICalPeriod.prepare(value.rule, value.duration, value.periods, context)
	}

	## Counts facts describing the mode, duration, PERIOD additions and effective
	## recurrence selectors. These facts do not retain original RRULE spelling.
	fact_count : ICalTimedRule -> U64
	fact_count = |rule| 2 + rule.periods.len() + TimedRecurrence.fact_count(rule.rule)
	## Returns the zero-based semantic fact, or End when the index is outside fact_count. Facts describe meaning, not a serialized record.
	fact_at : ICalTimedRule, U64 -> [End, Item(SemanticFact)]
	fact_at = |rule, index| {
		if index >= fact_count(rule) {
			return End
		}
		if index == 0 {
			return Item(SemanticFact.new(ICalTimedRuleDescription({ mode: rule.mode, period_count: rule.periods.len() })))
		}
		if index == 1 {
			context = match rule.mode {
				Utc => FixedUtc
				Floating | Zoned => Required
			}
			return Item(SemanticFact.new(RecurrencePolicy({ context, occurrence: First, gap: UseOffsetBeforeGap })))
		}
		if index == 2 {
			components = ICalDuration.components(rule.duration)
			return Item(SemanticFact.new(ICalDurationDescription({ role: RecurrenceEnding, days: components.days, seconds: components.seconds })))
		}
		remaining = index - 3
		if remaining < rule.periods.len() {
			return match rule.periods.get(remaining) {
				Ok(period) => ICalPeriod.fact_at(period, 0)
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
	## A concise semantic summary for debugging. Use the standard text encoder for storage or interchange.
	to_inspect : ICalTimedRule -> Str
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

local_text : LocalDateTime, ICalDateTime.Form, Str -> Try(Str, ICalTimedRule.Error)
local_text = |local, form, part| {
	date = match Calendar.Date.as_gregorian(LocalDateTime.date(local)) {
		Ok(gregorian) => GregorianDate.to_fields(gregorian)
		Err(_) => return Err(Unsupported("non-Gregorian ${part}"))
	}
	if date.year < 1 or date.year > 9999 {
		return Err(OutOfRange(part))
	}
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	if clock.microsecond != 0 {
		return Err(PrecisionLoss(part))
	}
	suffix = match form {
		Utc => "Z"
		Local => ""
	}
	Ok("${pad(date.year.to_str(), 4)}${pad(date.month.to_str(), 2)}${pad(date.day.to_str(), 2)}T${pad(clock.hour.to_str(), 2)}${pad(clock.minute.to_str(), 2)}${pad(clock.second.to_str(), 2)}${suffix}")
}

pad = |text, width| Str.repeat("0", width - text.count_utf8_bytes()).concat(text)

timestamp : Str, Str -> Try(ICalDateTime, ICalTimedRule.Error)
timestamp = |text, part| match ICalDateTime.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(DateTime(part, error))
}

timestamps : List(Str), Str, ICalDateTime.Form -> Try(List(ICalDateTime), ICalTimedRule.Error)
timestamps = |entries, part, form| {
	var $values = []
	for entry in entries {
		for text in entry.split_on(",") {
			if $values.len() == 4096 {
				return Err(TooLarge)
			}
			value = timestamp(text, part)?
			if ICalDateTime.form(value) != form {
				return Err(Unsupported("mixed ${part} and DTSTART forms"))
			}
			$values = $values.append(value)
		}
	}
	Ok($values)
}

# Keep UTC exclusions in their resolved domain. In particular, projecting a
# gap-adjusted start would lose its original source label.
exclusion_values = |entries, form, mode| {
	var $local = []
	var $boundaries = []
	var $count = 0.U64
	for entry in entries {
		for text in entry.split_on(",") {
			if $count == 4096 {
				return Err(TooLarge)
			}
			$count = $count + 1
			value = timestamp(text, "EXDATE")?
			if ICalDateTime.form(value) == form {
				$local = $local.append(value)
			} else if mode == Zoned and ICalDateTime.form(value) == Utc {
				boundary = match ICalDateTime.utc_boundary(value) {
					Ok(point) => point
					Err(_) => crash "validated UTC timestamp within year profile"
				}
				$boundaries = $boundaries.append(boundary)
			} else {
				return Err(Unsupported("mixed EXDATE and DTSTART forms"))
			}
		}
	}
	Ok({ local: $local, boundaries: $boundaries })
}

test_parts = |start, rule, mode| { start, rule, mode, duration: "P1D", inclusions: [], exclusions: [], periods: [] }

# Effective subdaily high fields must remain filters, while lower fields
# retain expansion. Reconstructing declarations must not replace them with
# DTSTART defaults or materialize the field product.
expect {
	var $valid = Bool.True
	for parts in [
		test_parts("20250101T090000Z", "FREQ=SECONDLY;INTERVAL=7;COUNT=3", Utc),
		test_parts("20250101T090000", "FREQ=MINUTELY;BYSECOND=0,30;COUNT=3", Floating),
		test_parts("20250101T090000", "FREQ=HOURLY;BYMINUTE=0,30;UNTIL=20250102T000000Z", Zoned),
		test_parts("20250101T090000", "FREQ=DAILY;UNTIL=20250102T090000", Floating),
	] {
		original = ICalTimedRule.parse(parts)?
		declaration = ICalTimedRule.definition(original)
		native = TimedRecurrence.definition(declaration.rule)
		rebuilt = TimedRecurrence.from_definition(native)?
		$valid = $valid and TimedRecurrence.definition(rebuilt) == native
		canonical = ICalTimedRule.to_parts(ICalTimedRule.new({ ..declaration, rule: rebuilt })?)?
		$valid = $valid and ICalTimedRule.to_parts(ICalTimedRule.parse(canonical)?)? == canonical
	}
	$valid
}

expect {
	parts = { ..test_parts("20250101T090000", "FREQ=WEEKLY;COUNT=4", Zoned), inclusions: ["20250104T090000"], exclusions: ["20250108T090000"], periods: ["20250115T090000/PT2H", "20250122T090000/20250122T113000"] }
	canonical = ICalTimedRule.to_parts(ICalTimedRule.parse(parts)?)?
	canonical.rule == "FREQ=WEEKLY;INTERVAL=1;COUNT=4;BYHOUR=9;BYMINUTE=0;BYSECOND=0;WKST=MO" and canonical.periods == ["20250115T090000/PT7200S", "20250122T090000/20250122T113000"] and canonical.inclusions == parts.inclusions and canonical.exclusions == parts.exclusions
}

test_timestamp = |text| match ICalDateTime.parse(text) {
	Ok(value) => value
	Err(_) => crash "valid timed-rule fixture timestamp"
}

test_observe = |parts, context, lower, upper| {
	parsed = match ICalTimedRule.parse(parts) {
		Ok(value) => value
		Err(error) => return Err(Parse(error))
	}
	window = { start: ICalDateTime.local_label(test_timestamp(lower)), end: ICalDateTime.local_label(test_timestamp(upper)) }
	var $cursor = ICalTimedRule.schedule(42.U64, parsed, window, context)?
	var $occurrences = []
	var $calls = 0.U64
	while $calls < 2000 {
		batch = match TimedSchedule.collect($cursor, { work: { max_steps: 3, max_buffered: 32, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(error) => return Err(Execution(error))
		}
		$occurrences = $occurrences.concat(batch.occurrences)
		match batch.status {
			Complete => return Ok($occurrences)
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	Err(FixtureDidNotTerminate)
}

# RFC COUNT is anchored before query restriction and exclusions. Invalid
# February/April 31st candidates do not consume it. PERIOD overrides May 31.
expect {
	parts = { ..test_parts("20250131T090000Z", "FREQ=MONTHLY;COUNT=3", Utc), exclusions: ["20250331T090000Z"], inclusions: ["20250415T090000Z,20250415T090000Z"], periods: ["20250531T090000Z/PT2H"] }
	values = test_observe(parts, Utc, "20250301T000000Z", "20250801T000000Z")?
	months = values.map(|value| Calendar.Date.to_fields(LocalDateTime.date(TimedRecurrence.Occurrence.source(TimedOccurrence.start(value)))).month)
	widths = values.map(|value| PosixSpan.coordinate_width(TimedOccurrence.span(value)))
	months == [4.U8, 5] and widths == [Ok(PosixDelta.from_microseconds(86400000000)), Ok(PosixDelta.from_microseconds(7200000000))]
}

# RFC 5545 section 3.8.5.3 and verified erratum 3883 (2014-02-14).
# https://www.rfc-editor.org/errata/eid3883
# The September 1997 New York fixture is UTC-04:00 throughout this window.
expect {
	validity = PosixSpan.new(ICalDateTime.utc_boundary(test_timestamp("19970901T000000Z"))?, ICalDateTime.utc_boundary(test_timestamp("19970904T000000Z"))?)?
	rules = ZoneRules.new_bounded("RFC5545/New_York", "1997-example", validity, FixedOffset.from_seconds(-14400), [], { minimum: -14400, maximum: -14400 })?
	var $valid = Bool.True
	for case in [{ until: "19970902T210000Z", expected: [9.U8, 12, 15] }, { until: "19970902T170000Z", expected: [9, 12] }, { until: "19970902T190000Z", expected: [9, 12, 15] }] {
		parts = { ..test_parts("19970902T090000", "FREQ=HOURLY;INTERVAL=3;UNTIL=${case.until}", Zoned), duration: "PT1H" }
		values = test_observe(parts, Local(rules), "19970902T000000", "19970903T000000")?
		$valid = $valid and values.map(|value| ClockTime.to_fields(LocalDateTime.clock(TimedRecurrence.Occurrence.source(TimedOccurrence.start(value)))).hour) == case.expected
	}
	$valid
}

expect {
	var $valid = Bool.True
	for parts in [test_parts("20250101T090000Z", "FREQ=DAILY;UNTIL=20250102T090000", Utc), test_parts("20250101T090000", "FREQ=DAILY;UNTIL=20250102T090000Z", Floating), test_parts("20250101T090000", "FREQ=DAILY;UNTIL=20250102T090000", Zoned), test_parts("20250101T090000Z", "FREQ=DAILY", Zoned)] {
		$valid = $valid and match ICalTimedRule.parse(parts) {
			Err(Incompatible(_)) => Bool.True
			_ => Bool.False
		}
	}
	$valid
}
expect {
	parts = { ..test_parts("20070311T023000", "FREQ=HOURLY;COUNT=2", Zoned), exclusions: ["20070311T073000Z"] }
	parsed = ICalTimedRule.parse(parts)?
	data = TimedRecurrence.definition(ICalTimedRule.definition(parsed).rule)
	floating = match ICalTimedRule.parse({ ..parts, mode: Floating }) {
		Err(Unsupported("mixed EXDATE and DTSTART forms")) => Bool.True
		_ => Bool.False
	}
	boundary = PosixBoundary.from_microseconds(1173598200000000)
	data.exclusions.is_empty() and data.boundary_exclusions == [boundary] and ICalTimedRule.profile == "rfc5545-timed-values" and ICalTimedRule.to_parts(parsed)?.exclusions == parts.exclusions and ICalTimedRule.fact_at(parsed, ICalTimedRule.fact_count(parsed) - 1) == Item(SemanticFact.new(RecurrenceBoundaryExclusion(boundary))) and floating
}
expect {
	parts = test_parts("20250101T090000Z", "FREQ=DAILY;BYSECOND=60", Utc)
	match ICalTimedRule.parse(parts) {
		Err(InvalidRule(UnsupportedLeapSecond)) => Bool.True
		_ => Bool.False
	}
}
expect {
	parts = test_parts("20250101T090000Z", "FREQ=DAILY;COUNT=1;COUNT=2", Utc)
	match ICalTimedRule.parse(parts) {
		Err(Rule(Duplicate("COUNT"))) => Bool.True
		_ => Bool.False
	}
}

expect {
	rule = ICalTimedRule.parse({ start: "20250101T090000", rule: "FREQ=DAILY;COUNT=1", duration: "P1D", inclusions: [], exclusions: ["20250101T090000"], periods: [], mode: Zoned })?
	# Exclusion preserves the one-count declaration; no occurrence is generated
	# merely to explain it. Wrapper mode supplies RFC gap/fold policy.
	ICalTimedRule.fact_at(rule, 0) == Item(SemanticFact.new(ICalTimedRuleDescription({ mode: Zoned, period_count: 0 }))) and ICalTimedRule.fact_at(rule, 1) == Item(SemanticFact.new(RecurrencePolicy({ context: Required, occurrence: First, gap: UseOffsetBeforeGap }))) and ICalTimedRule.fact_at(rule, 2) == Item(SemanticFact.new(ICalDurationDescription({ role: RecurrenceEnding, days: 1, seconds: 0 }))) and ICalTimedRule.fact_at(rule, 4) == Item(SemanticFact.new(RecurrenceTermination(Count(1)))) and ICalTimedRule.fact_at(rule, ICalTimedRule.fact_count(rule)) == End and ICalTimedRule.fact_at(rule, U64.highest) == End and ICalTimedRule.to_inspect(rule).count_utf8_bytes() <= 256
}
