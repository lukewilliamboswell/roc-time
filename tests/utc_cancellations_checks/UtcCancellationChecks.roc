import time.ICalTimedRule
import time.ICalDateTime
import time.TimedRecurrence
import time.TimedSchedule
import time.TimedOccurrence
import time.ScheduleDefinition
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.PosixDelta
import time.ZoneRules
import time.FixedOffset
import time.Explanation
import time.SemanticFact

# R07/R09/R10/R11/R12/R14/R16. Expected positions below come from explicit
# RFC labels/offsets and an independent epoch model, never package execution.
UtcCancellationChecks :: [].{
	run = |suffix| {
		synthetic(suffix)
		new_york(suffix)
		invalid_profiles(suffix)
	}
}

parts = |start, rule, exclusions| { start, rule, exclusions, mode: Zoned, duration: "PT1H", inclusions: [], periods: [] }

expected = |source, position, width| { source, position, width }

synthetic = |suffix| {
	validity = PosixSpan.from_seconds(-172800, 345600, RejectSubmicrosecond) ?? crash "Synthetic validity"
	rules = ZoneRules.new_bounded("Synthetic/Cancellation", "epoch-gap-v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(3600) }], { minimum: 0, maximum: 3600 }) ?? crash "Synthetic rules"
	base = parts("19691231T003000", "FREQ=DAILY;COUNT=4;BYHOUR=0,1;BYMINUTE=30", ["19700101T003000Z"])
	before = [expected("1969-12-31T00:30:00", -84600000000, 3600000000), expected("1969-12-31T01:30:00", -81000000000, 3600000000)]
	verify(base, rules, "19691231T000000", "19700103T000000", before, suffix)
	# A second window cannot replenish COUNT after the two colliding starts
	# were counted and then cancelled. The overlap contains no survivors.
	verify(base, rules, "19700101T000000", "19700103T000000", [], suffix)
	# A source exclusion removes only 00:30; 01:30 has the same boundary but
	# retains its distinct original identity. This is the projection counterexample.
	verify({ ..base, exclusions: ["19700101T003000"] }, rules, "19691231T000000", "19700103T000000", before.append(expected("1970-01-01T01:30:00", 1800000000, 3600000000)), suffix)
	verify({ ..base, exclusions: ["19691231T003000", "19700101T003000Z", "19700101T003000Z"] }, rules, "19691231T000000", "19700103T000000", [expected("1969-12-31T01:30:00", -81000000000, 3600000000)], suffix)
	added = {
		..parts("19691231T003000", "FREQ=DAILY;COUNT=1", ["19700101T003000Z"]),
		inclusions: ["19700101T003000,19700101T013000"],
		periods: ["19700101T013000/PT2H", "19700101T023000/PT3H"],
	}
	verify(added, rules, "19691231T000000", "19700103T000000", [before.get(0) ?? crash "Fixture", expected("1970-01-01T02:30:00", 5400000000, 10800000000)], suffix)
	# Both selected source positions map to the cancelled boundary; neither
	# cancellation changes BYSETPOS membership or lets a later day replace COUNT.
	positioned = parts("19700101T003000", "FREQ=DAILY;COUNT=2;BYHOUR=0,1;BYMINUTE=30;BYSETPOS=1,-1", ["19700101T003000Z"])
	verify(positioned, rules, "19700101T000000", "19700103T000000", [], suffix)
}

new_york = |suffix| {
	# RFC 5545 §3.3.5: 2007-03-11 02:30 uses pre-gap -05:00,
	# yielding 07:30Z; 2007-11-04 01:30 selects first -04:00, 05:30Z.
	spring = ZoneRules.new_bounded("RFC5545/New_York", "2007-spring-fixture", PosixSpan.new(point(1173398400000000), point(1173744000000000)) ?? crash "Spring validity", FixedOffset.from_seconds(-18000), [{ at: point(1173596400000000), offset: FixedOffset.from_seconds(-14400) }], { minimum: -18000, maximum: -14400 }) ?? crash "Spring rules"
	spring_parts = parts("20070310T023000", "FREQ=DAILY;COUNT=3", ["20070311T073000Z"])
	verify(
		spring_parts,
		spring,
		"20070310T000000",
		"20070313T000000",
		[
			expected("2007-03-10T02:30:00", 1173511800000000, 3600000000),
			expected("2007-03-12T02:30:00", 1173681000000000, 3600000000),
		],
		suffix,
	)
	# An adjacent wrong UTC exclusion must not cancel the adjusted source.
	verify({ ..spring_parts, exclusions: ["20070311T063000Z"] }, spring, "20070311T000000", "20070312T000000", [expected("2007-03-11T02:30:00", 1173598200000000, 3600000000)], suffix)
	fall = ZoneRules.new_bounded("RFC5545/New_York", "2007-fall-fixture", PosixSpan.new(point(1193961600000000), point(1194307200000000)) ?? crash "Fall validity", FixedOffset.from_seconds(-14400), [{ at: point(1194156000000000), offset: FixedOffset.from_seconds(-18000) }], { minimum: -18000, maximum: -14400 }) ?? crash "Fall rules"
	fall_parts = parts("20071103T013000", "FREQ=DAILY;COUNT=3", ["20071104T063000Z"])
	verify(fall_parts, fall, "20071104T000000", "20071105T000000", [expected("2007-11-04T01:30:00", 1194154200000000, 3600000000)], suffix)
	verify(
		{ ..fall_parts, exclusions: ["20071104T053000Z"] },
		fall,
		"20071103T000000",
		"20071106T000000",
		[
			expected("2007-11-03T01:30:00", 1194067800000000, 3600000000),
			expected("2007-11-05T01:30:00", 1194244200000000, 3600000000),
		],
		suffix,
	)
}

verify = |input, rules, lower, upper, expected_values, suffix| {
	original = ICalTimedRule.parse(input) ?? crash "UTC cancellation import rejected"
	data = TimedRecurrence.definition(ICalTimedRule.definition(original).rule)
	explanation = Explanation.new(ICalTimedRule(original))
	count = Explanation.fact_count(explanation)
	var $fact = count - data.boundary_exclusions.len()
	for boundary in data.boundary_exclusions {
		if Explanation.fact_at(explanation, $fact) != Item(SemanticFact.new(RecurrenceBoundaryExclusion(boundary))) {
			crash "Explanation changed cancellation domain"
		}
		$fact = $fact + 1
	}
	report = Explanation.plain(explanation, { max_facts: count, max_utf8_bytes: 16384 })
	if report.status != Complete or (!data.boundary_exclusions.is_empty() and !report.text.contains("selected POSIX boundary")) {
		crash "Bounded cancellation explanation lost its meaning"
	}
	exported = ICalTimedRule.to_parts(original) ?? crash "UTC cancellation export rejected"
	roundtrip = ICalTimedRule.parse(exported) ?? crash "UTC cancellation export cannot import"
	definition = ScheduleDefinition.from_ical({ rule: roundtrip, context: Local(rules) }) ?? crash "UTC cancellation definition rejected"
	if ICalTimedRule.to_parts(roundtrip) != Ok(exported) {
		crash "Canonical RFC properties changed on reimport"
	}
	window = { start: label(lower), end: label(upper) }
	series = "cancel${suffix}"
	direct = ICalTimedRule.schedule(series, original, window, Local(rules)) ?? crash "Original schedule rejected"
	reimported = ScheduleDefinition.cursor(series, definition, window) ?? crash "Reimported cursor rejected"
	if collect(direct, Bool.False, series) != expected_values or collect(reimported, Bool.True, series) != expected_values {
		crash "UTC cancellations differ from independent model"
	}
}

collect = |initial, tiny, series| {
	var $cursor = initial
	var $observed = []
	var $calls = 0.U64
	while $calls < 20000 {
		batch = TimedSchedule.collect(
			$cursor,
			{
				work: {
					max_steps: if tiny {
						2
					} else {
						10000
					},
					max_buffered: 16,
					max_zone_segments: if tiny {
						1
					} else {
						100
					},
					max_zone_candidates: 2,
				},
				max_occurrences: if tiny {
					1
				} else {
					32
				},
			},
		) ?? crash "UTC cancellation evaluation failed"
		if tiny and (batch.steps > 2 or batch.zone_segments > 1 or batch.occurrences.len() > 1) {
			crash "Cancellation budget exceeded"
		}
		for item in batch.occurrences {
			identity = TimedOccurrence.id(item)
			if identity.series != series or identity.source != TimedOccurrence.source(item) {
				crash "Cancellation identity changed"
			}
			source = LocalDateTime.to_gregorian_text(identity.source) ?? crash "Fixture source calendar"
			span = TimedOccurrence.span(item)
			width = PosixSpan.coordinate_width(span) ?? crash "Fixture span width"
			$observed = $observed.append({ source, position: PosixBoundary.to_microseconds(PosixSpan.start(span)), width: PosixDelta.to_microseconds(width) })
		}
		match batch.status {
			Complete => return $observed
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "Cancellation bounded resumption did not finish"
}

invalid_profiles = |suffix| {
	base = parts("19700101T003000", "FREQ=DAILY;COUNT=1", [])
	for bad in [{ ..base, mode: Floating, exclusions: ["19700101T003000Z"] }, { ..base, inclusions: ["19700101T003000Z"] }, { ..base, periods: ["19700101T003000Z/PT1H"] }] {
		match ICalTimedRule.parse(bad) {
			Err(Unsupported(_)) => {}
			_ => crash "Unsupported mixed property silently accepted"
		}
	}
	match ICalTimedRule.parse({ ..base, exclusions: ["not-a-date${suffix}"] }) {
		Err(DateTime("EXDATE", _)) => {}
		_ => crash "Malformed UTC cancellation not structured"
	}
}

point = |micros| PosixBoundary.from_microseconds(micros)

label = |text| ICalDateTime.local_label(ICalDateTime.parse(text) ?? crash "Fixture label")
