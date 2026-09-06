import RfcRuleParts
import RfcDateTime
import CalendarPattern
import DateRecurrence
import GregorianDate

## RFC 5545 DATE recurrence value adapter, profile date-values-v1.
## Input fields are already extracted property values, not content lines or an
## ICS document. DTSTART/RDATE/EXDATE/UNTIL use YYYYMMDD, years 0001–9999.
## DAILY/WEEKLY/MONTHLY/YEARLY, date selectors, WKST, COUNT and UNTIL are
## supported. Return the same DateRecurrence used by native constructors.
## Timed values, subdaily frequencies, extensions and implicit YEARLY defaults
## described below are explicit unsupported scopes. No source spelling,
## serialization, full iCalendar, or full RFC conformance claim is made.
##
## Example
##
## Parse extracted property values, then use the ordinary recurrence cursor.
## These inputs are values, not complete `DTSTART:` lines or an ICS document.
## Timed values and unsupported extensions return explicit errors.
##
## ```roc
## import time.RfcDateRule
## import time.GregorianDate
## import time.DateRecurrence
##
## expect {
##     rule = RfcDateRule.parse({
##         start: "20250131",
##         rule: "FREQ=MONTHLY;COUNT=3",
##         inclusions: [],
##         exclusions: ["20250331"],
##     })?
##     start = GregorianDate.from_fields({ year: 2025, month: 1, day: 1 })?
##     end = GregorianDate.from_fields({ year: 2025, month: 6, day: 1 })?
##     cursor = DateRecurrence.cursor(rule, { start, end })?
##     batch = DateRecurrence.Cursor.collect(cursor, {
##         max_steps: 1000, max_buffered: 31, max_occurrences: 4,
##     })?
##     batch.dates.map(|date| GregorianDate.to_fields(date).month) == [1.U8, 5]
## }
## ```
##
## Examples assume a package dependency named `time`.
RfcDateRule :: [].{
	profile : Str
	profile = "rfc5545-date-values-v1"
	Parts : { start : Str, rule : Str, inclusions : List(Str), exclusions : List(Str) }
	Error : [Malformed(Str), Duplicate(Str), Missing(Str), Unsupported(Str), OutOfRange(Str), Incompatible(Str), InvalidDate(Str), TooLarge, InvalidRule([InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), InvalidCount, InvalidUntil, UnsynchronizedStart, OutOfRange])]

	## At most 65536 input bytes in total and 4096 supplied inclusion/exclusion
	## strings each. RDATE/EXDATE entries may contain comma-separated dates;
	## each expanded list and selector list is limited to 4096 values.
	## Parse O(input bytes + supplied entries), then bounded DateRecurrence construction. Never
	## expand a series here. Names/enumerations are ASCII case-insensitive;
	## whitespace, folded lines, duplicate keys and numeric overflow are errors.
	parse : Parts -> Try(DateRecurrence, Error)
	parse = |parts| {
		if parts.inclusions.len() > 4096 or parts.exclusions.len() > 4096 {
			return Err(TooLarge)
		}
		var remaining = 65536.U64
		for value in [parts.start, parts.rule].concat(parts.inclusions).concat(parts.exclusions) {
			if value.count_utf8_bytes() > remaining {
				return Err(TooLarge)
			}
			remaining = remaining - value.count_utf8_bytes()
		}
		anchor = parse_date(parts.start, "DTSTART")?
		fields = match RfcRuleParts.parse(parts.rule, Date) {
			Ok(value) => value
			Err(Malformed(part)) => return Err(Malformed(part))
			Err(Duplicate(part)) => return Err(Duplicate(part))
			Err(Missing(part)) => return Err(Missing(part))
			Err(Unsupported(part)) => return Err(Unsupported(part))
			Err(OutOfRange(part)) => return Err(OutOfRange(part))
			Err(Incompatible(part)) => return Err(Incompatible(part))
			Err(TooLarge) => return Err(TooLarge)
		}
		termination = match fields.termination {
			Forever => Forever
			Count(count) => Count(count)
			Until(text) => Until(parse_date(text, "UNTIL")?)
		}
		inclusions = parse_dates(parts.inclusions, "RDATE")?
		exclusions = parse_dates(parts.exclusions, "EXDATE")?
		match DateRecurrence.new(anchor, { pattern: fields.pattern, termination, by_set_pos: fields.positions, inclusions, exclusions }) {
			Ok(rule) => Ok(rule)
			Err(error) => Err(InvalidRule(error))
		}
	}
}

parse_date : Str, Str -> Try(GregorianDate, RfcDateRule.Error)
parse_date = |text, part| {
	bytes = text.to_utf8()
	if bytes.len() != 8 {
		# Share DATE-TIME validation with the timed adapter. A recognized leap
		# second is still a DATE-TIME/DATE mismatch in this date-only profile.
		return match RfcDateTime.parse(text) {
			Ok(_) | Err(UnsupportedLeapSecond) => Err(Incompatible("DATE-TIME with DATE"))
			Err(OutOfRange) => Err(OutOfRange(part))
			Err(InvalidDate) => Err(InvalidDate(part))
			Err(_) => Err(Malformed(part))
		}
	}
	var value = 0.I64
	for byte in bytes {
		if byte < 48 or byte > 57 {
			return Err(Malformed(part))
		}
		value = value * 10 + byte.to_i64() - 48
	}
	year = I64.div_trunc_by(value, 10000)
	if year == 0 {
		return Err(OutOfRange(part))
	}
	# Eight decimal digits establish exact narrowing for the two-digit fields.
	month = I64.mod_by(I64.div_trunc_by(value, 100), 100).to_u8_wrap()
	day = I64.mod_by(value, 100).to_u8_wrap()
	match GregorianDate.from_fields({ year, month, day }) {
		Ok(date) => Ok(date)
		Err(_) => Err(InvalidDate(part))
	}
}

parse_dates : List(Str), Str -> Try(List(GregorianDate), RfcDateRule.Error)
parse_dates = |entries, part| {
	var dates = []
	for entry in entries {
		for value in entry.split_on(",") {
			if dates.len() == 4096 {
				return Err(TooLarge)
			}
			dates = dates.append(parse_date(value, part)?)
		}
	}
	Ok(dates)
}

test_rfcdaterule_parts = |start, rule| { start, rule, inclusions: [], exclusions: [] }

test_rfcdaterule_status = |input| match RfcDateRule.parse(input) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

test_rfcdaterule_date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid fixture test_rfcdaterule_date"
}

test_rfcdaterule_observe = |input, test_rfcdaterule_window| {
	rule = RfcDateRule.parse(input)?
	cursor = match DateRecurrence.cursor(rule, test_rfcdaterule_window) {
		Ok(value) => value
		Err(_) => crash "Invalid fixture query"
	}
	batch = match DateRecurrence.Cursor.collect(cursor, { max_steps: 10000, max_buffered: 366, max_occurrences: 100 }) {
		Ok(value) => value
		Err(_) => crash "Fixture outside provider range"
	}
	match batch.status {
		Complete => Ok(batch.dates)
		Limited(_) => crash "Unexpected fixture limit"
	}
}

test_rfcdaterule_window = { start: test_rfcdaterule_date(2025, 1, 1), end: test_rfcdaterule_date(2026, 1, 1) }

# RFC 5545 §3.3.10 invalid dates/COUNT and §3.8.5 exclusions.
expect {
	input = { ..test_rfcdaterule_parts("20250131", "FREQ=MONTHLY;COUNT=3"), inclusions: ["20250704,20250331"], exclusions: ["20250331"] }
	test_rfcdaterule_observe(input, test_rfcdaterule_window)? == [test_rfcdaterule_date(2025, 1, 31), test_rfcdaterule_date(2025, 5, 31), test_rfcdaterule_date(2025, 7, 4)] and
		test_rfcdaterule_observe(input, { ..test_rfcdaterule_window, start: test_rfcdaterule_date(2025, 3, 1) })? == [test_rfcdaterule_date(2025, 5, 31), test_rfcdaterule_date(2025, 7, 4)]
}

expect {
	test_rfcdaterule_observe(test_rfcdaterule_parts("20250131", "count=03;ByDaY=mo,tu,we,th,fr;bysetpos=-1;freq=monthly"), test_rfcdaterule_window)? ==
		[test_rfcdaterule_date(2025, 1, 31), test_rfcdaterule_date(2025, 2, 28), test_rfcdaterule_date(2025, 3, 31)]
}

expect {
	test_rfcdaterule_observe(test_rfcdaterule_parts("20250101", "BYMONTH=01,06;BYMONTHDAY=+01;FREQ=YEARLY;UNTIL=20250601"), test_rfcdaterule_window)? ==
		[test_rfcdaterule_date(2025, 1, 1), test_rfcdaterule_date(2025, 6, 1)]
}

# Date projection of RFC 5545 §3.8.5.3's WKST example (August 1997).
expect {
	query = { start: test_rfcdaterule_date(1997, 8, 1), end: test_rfcdaterule_date(1997, 9, 1) }
	test_rfcdaterule_observe(test_rfcdaterule_parts("19970805", "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU"), query)? ==
		[test_rfcdaterule_date(1997, 8, 5), test_rfcdaterule_date(1997, 8, 17), test_rfcdaterule_date(1997, 8, 19), test_rfcdaterule_date(1997, 8, 31)] and
		test_rfcdaterule_observe(test_rfcdaterule_parts("19970805", "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO"), query)? ==
			[test_rfcdaterule_date(1997, 8, 5), test_rfcdaterule_date(1997, 8, 10), test_rfcdaterule_date(1997, 8, 19), test_rfcdaterule_date(1997, 8, 24)]
}

expect {
	test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "COUNT=3")) == Err(Missing("FREQ")) and
		test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;freq=DAILY")) == Err(Duplicate("FREQ")) and
			test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;COUNT=3;UNTIL=20250131")) == Err(Incompatible("COUNT and UNTIL")) and
				test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;BYSETPOS=1")) == Err(Incompatible("BYSETPOS requires another BY selector"))
}

expect {
	var passed = True
	for text in ["FREQ=DAILY;", "FREQ=DAILY;;COUNT=2", "FREQ=DAILY;COUNT=", "FREQ=DAILY;COUNT=+2", "FREQ=DAILY;COUNT=1_0", "FREQ=DAILY;COUNT=1.0", "FREQ=DAILY;BYMONTH=001", "FREQ=DAILY;BYMONTH=+1", "FREQ=DAILY;BYDAY=+MO", "FREQ=DAILY;BYDAY=001MO", "FREQ=DAILY;BYMONTH=1,", "FREQ=DAILY\n", "FREQ= DAILy", "FREQ=DAILY;COUNT=٢"] {
		match test_rfcdaterule_status(test_rfcdaterule_parts("20250101", text)) {
			Err(Malformed(_)) => {}
			_ => {
				passed = False
			}
		}
	}
	passed
}

expect {
	var passed = True
	for text in ["FREQ=DAILY;COUNT=0", "FREQ=DAILY;COUNT=2147483648", "FREQ=DAILY;INTERVAL=99999999999999999999999", "FREQ=DAILY;BYMONTH=13", "FREQ=MONTHLY;BYDAY=0MO", "FREQ=MONTHLY;BYMONTHDAY=-00", "FREQ=YEARLY;BYYEARDAY=367", "FREQ=YEARLY;BYWEEKNO=-54"] {
		match test_rfcdaterule_status(test_rfcdaterule_parts("20250101", text)) {
			Err(OutOfRange(_)) => {}
			_ => {
				passed = False
			}
		}
	}
	passed
}

expect {
	test_rfcdaterule_status(test_rfcdaterule_parts("20250229", "FREQ=DAILY")) == Err(InvalidDate("DTSTART")) and
		test_rfcdaterule_status(test_rfcdaterule_parts("00000101", "FREQ=DAILY")) == Err(OutOfRange("DTSTART")) and
			test_rfcdaterule_status(test_rfcdaterule_parts("2025-01-01", "FREQ=DAILY")) == Err(Malformed("DTSTART")) and
				test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;UNTIL=20250131T000000Z")) == Err(Incompatible("DATE-TIME with DATE")) and
					test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;UNTIL=T")) == Err(Malformed("UNTIL")) and
						test_rfcdaterule_status({ ..test_rfcdaterule_parts("20250101", "FREQ=DAILY"), exclusions: ["20250230"] }) == Err(InvalidDate("EXDATE"))
}

expect {
	test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=HOURLY")) == Err(Unsupported("subdaily DATE recurrence")) and
		test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;BYHOUR=12")) == Err(Incompatible("clock selector with DATE")) and
			test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=YEARLY;RSCALE=HEBREW")) == Err(Unsupported("RSCALE")) and
				test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;X-SKIP=FORWARD")) == Err(Unsupported("X-SKIP"))
}

expect {
	test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=YEARLY;BYMONTHDAY=1")) == Err(Unsupported("YEARLY BYMONTHDAY requires explicit BYMONTH in this profile")) and
		test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=YEARLY;BYWEEKNO=1")) == Err(Unsupported("YEARLY BYWEEKNO requires explicit BYDAY in this profile")) and
			test_rfcdaterule_status(test_rfcdaterule_parts("20250120", "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-1")) == Err(InvalidRule(UnsynchronizedStart)) and
				test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=WEEKLY;BYMONTHDAY=1")) == Err(InvalidRule(InvalidCombination("BYMONTHDAY with WEEKLY")))
}

expect {
	test_rfcdaterule_status(test_rfcdaterule_parts("20250101", Str.repeat("x", 65537))) == Err(TooLarge) and
		test_rfcdaterule_status({ ..test_rfcdaterule_parts("20250101", "FREQ=DAILY"), inclusions: List.repeat("20250101", 4097) }) == Err(TooLarge) and
			test_rfcdaterule_status(test_rfcdaterule_parts("20250101", "FREQ=DAILY;BYMONTH=${Str.join_with(List.repeat("1", 4097), ",")}")) == Err(TooLarge)
}
