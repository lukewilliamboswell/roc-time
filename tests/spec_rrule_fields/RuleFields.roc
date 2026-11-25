import time.ICalendar.DateRule as ICalDateRule
import time.ICalendar.TimedRule as ICalTimedRule
import time.ICalendar.DateTime as ICalDateTime
import time.Recurrence.Date as DateRecurrence
import time.Recurrence.DateCursor as DateCursor
import time.PosixBoundary
import time.PosixSpan
import time.GregorianDate

RuleFields := {}

# R11/R14. RFC 5545 §3.3.10 accepts rule parts in any order and signed
# BYYEARDAY magnitudes of one to three digits. 1972 is a leap year, so
# day -366 equals January 1, and day +366 is December 31. Input rotation
# places each field first once. Canonical text and dates are fixed separately.
expect {
	fields = ["byyearday=+366,-366,+001,+366", "count=02", "freq=yearly", "interval=0001", "wkst=mo"]
	canonical = "FREQ=YEARLY;INTERVAL=1;COUNT=2;BYYEARDAY=-366,1,366;WKST=MO"
	for shift in 0.U64..<fields.len() {
		text = Str.join_with(fields.drop_first(shift).concat(fields.take_first(shift)), ";")
		rule = ICalDateRule.parse({ start: "19720101", rule: text, inclusions: [], exclusions: [] })?
		if ICalDateRule.to_parts(rule)?.rule != canonical {
			crash "Wrong canonical DATE selectors for ${text}"
		}
	}
	rule = ICalDateRule.parse({ start: "19720101", rule: canonical, inclusions: [], exclusions: [] })?
	cursor = DateRecurrence.cursor(rule, { start: date(1972, 1, 1), end: date(1973, 1, 1) })?
	batch = DateCursor.collect(cursor, { max_steps: 1024, max_buffered: 366, max_occurrences: 4 })?
	match batch.status {
		Complete => batch.dates == [date(1972, 1, 1), date(1972, 12, 31)]
		_ => False
	}
}

# RFC 5545 §3.3.10's table limits subdaily candidates with BYYEARDAY.
# December 31, 1969 is both day +365 and day -1, and 1970's January 1
# matches neither. Every rule's four unfiltered slots straddle the epoch.
# Explicit hour/minute/second sets admit all four to isolate the date filter.
expect {
	cases = [
		{ frequency: "SECONDLY", start: "19691231T235958Z", stop: "19700101T000002Z", clock: "BYHOUR=0,23;BYMINUTE=0,59;BYSECOND=0,1,58,59", coordinates: [-2000000.I64, -1000000] },
		{ frequency: "MINUTELY", start: "19691231T235800Z", stop: "19700101T000200Z", clock: "BYHOUR=0,23;BYMINUTE=0,1,58,59;BYSECOND=0", coordinates: [-120000000, -60000000] },
		{ frequency: "HOURLY", start: "19691231T220000Z", stop: "19700101T020000Z", clock: "BYHOUR=0,1,22,23;BYMINUTE=0;BYSECOND=0", coordinates: [-7200000000, -3600000000] },
	]
	for case in cases {
		text = "BYYEARDAY=+365,-001,+366;COUNT=04;${case.clock};FREQ=${case.frequency}"
		rule = ICalTimedRule.parse({ start: case.start, rule: text, mode: Utc, duration: "PT1S" })?
		expected = "FREQ=${case.frequency};INTERVAL=1;COUNT=4;BYYEARDAY=-1,365,366;${case.clock};WKST=MO"
		if ICalTimedRule.to_parts(rule)?.rule != expected {
			crash "Timed ${case.frequency} changed BYYEARDAY or its clock filters"
		}
		cursor = ICalTimedRule.schedule({ series: 1.U64, rule, context: Utc, window: { start: label(case.start), end: label(case.stop) } })?
		batch = cursor.collect({ work: { max_steps: 64, max_buffered: 4, max_zone_segments: 16, max_zone_candidates: 1 }, max_occurrences: 5 })?
		coordinates = batch.occurrences.map(|value| PosixBoundary.to_microseconds(PosixSpan.start(value.span())))
		match batch.status {
			Complete => {}
			Limited(detail) => crash "Short epoch fixture ${case.frequency} did not terminate: ${Str.inspect(detail)}"
		}
		if coordinates != case.coordinates {
			crash "Wrong ${case.frequency} positions ${Str.inspect(coordinates)}"
		}
	}
	True
}

# A year-day list is unavailable to DAILY/WEEKLY/MONTHLY. Lexical width,
# numeric bounds and frequency incompatibility are distinct public errors.
expect {
	for frequency in ["DAILY", "WEEKLY", "MONTHLY"] {
		text = "BYYEARDAY=-001;FREQ=${frequency}"
		if date_status(text) != Err(InvalidRule(InvalidCombination("BYYEARDAY requires YEARLY"))) or
			timed_status(text) != Err(InvalidRule(InvalidCombination("BYYEARDAY requires YEARLY"))) {
			crash "Wrong BYYEARDAY exclusion for ${frequency}"
		}
	}
	for token in ["+0001", "0366", "+-1", "1,", "--2"] {
		text = "BYYEARDAY=${token};FREQ=YEARLY"
		if date_status(text) != Err(Malformed("BYYEARDAY")) or timed_status(text) != Err(Rule(Malformed("BYYEARDAY"))) {
			crash "Wrong year-day syntax error for ${token}"
		}
	}
	for token in ["+000", "0", "-000", "+367", "-367"] {
		text = "BYYEARDAY=${token};FREQ=YEARLY"
		if date_status(text) != Err(OutOfRange("BYYEARDAY")) or timed_status(text) != Err(Rule(OutOfRange("BYYEARDAY"))) {
			crash "Wrong year-day range error for ${token}"
		}
	}
	True
}

date = |year, month, day| GregorianDate.from_fields({ year, month, day }) ?? crash "fixture date"

label = |text| ICalDateTime.local_label(ICalDateTime.parse(text) ?? crash "fixture date-time")

date_status : Str -> Try({}, ICalDateRule.Error)
date_status = |text| match ICalDateRule.parse({ start: "19721231", rule: text, inclusions: [], exclusions: [] }) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

timed_status : Str -> Try({}, ICalTimedRule.Error)
timed_status = |text| match ICalTimedRule.parse({ start: "19721231T230000Z", rule: text, mode: Utc, duration: "PT1S" }) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
