import RfcDateRule
import DateRecurrence
import GregorianDate

RfcDateRuleTests :: [].{}

parts = |start, rule| { start, rule, inclusions: [], exclusions: [] }

status = |input| match RfcDateRule.parse(input) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid fixture date"
}

observe = |input, window| {
	rule = RfcDateRule.parse(input)?
	cursor = match DateRecurrence.cursor(rule, window) {
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

window = { start: date(2025, 1, 1), end: date(2026, 1, 1) }

# RFC 5545 §3.3.10 invalid dates/COUNT and §3.8.5 exclusions.
expect {
	input = { ..parts("20250131", "FREQ=MONTHLY;COUNT=3"), inclusions: ["20250704,20250331"], exclusions: ["20250331"] }
	observe(input, window)? == [date(2025, 1, 31), date(2025, 5, 31), date(2025, 7, 4)] and
		observe(input, { ..window, start: date(2025, 3, 1) })? == [date(2025, 5, 31), date(2025, 7, 4)]
}

expect {
	observe(parts("20250131", "count=03;ByDaY=mo,tu,we,th,fr;bysetpos=-1;freq=monthly"), window)? ==
		[date(2025, 1, 31), date(2025, 2, 28), date(2025, 3, 31)]
}

expect {
	observe(parts("20250101", "BYMONTH=01,06;BYMONTHDAY=+01;FREQ=YEARLY;UNTIL=20250601"), window)? ==
		[date(2025, 1, 1), date(2025, 6, 1)]
}

# Date projection of RFC 5545 §3.8.5.3's WKST example (August 1997).
expect {
	query = { start: date(1997, 8, 1), end: date(1997, 9, 1) }
	observe(parts("19970805", "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU"), query)? ==
		[date(1997, 8, 5), date(1997, 8, 17), date(1997, 8, 19), date(1997, 8, 31)] and
		observe(parts("19970805", "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO"), query)? ==
			[date(1997, 8, 5), date(1997, 8, 10), date(1997, 8, 19), date(1997, 8, 24)]
}

expect {
	status(parts("20250101", "COUNT=3")) == Err(Missing("FREQ")) and
		status(parts("20250101", "FREQ=DAILY;freq=DAILY")) == Err(Duplicate("FREQ")) and
			status(parts("20250101", "FREQ=DAILY;COUNT=3;UNTIL=20250131")) == Err(Incompatible("COUNT and UNTIL")) and
				status(parts("20250101", "FREQ=DAILY;BYSETPOS=1")) == Err(Incompatible("BYSETPOS requires another BY selector"))
}

expect {
	var passed = True
	for text in ["FREQ=DAILY;", "FREQ=DAILY;;COUNT=2", "FREQ=DAILY;COUNT=", "FREQ=DAILY;COUNT=+2", "FREQ=DAILY;COUNT=1_0", "FREQ=DAILY;COUNT=1.0", "FREQ=DAILY;BYMONTH=001", "FREQ=DAILY;BYMONTH=+1", "FREQ=DAILY;BYDAY=+MO", "FREQ=DAILY;BYDAY=001MO", "FREQ=DAILY;BYMONTH=1,", "FREQ=DAILY\n", "FREQ= DAILy", "FREQ=DAILY;COUNT=٢"] {
		match status(parts("20250101", text)) {
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
		match status(parts("20250101", text)) {
			Err(OutOfRange(_)) => {}
			_ => {
				passed = False
			}
		}
	}
	passed
}

expect {
	status(parts("20250229", "FREQ=DAILY")) == Err(InvalidDate("DTSTART")) and
		status(parts("00000101", "FREQ=DAILY")) == Err(OutOfRange("DTSTART")) and
			status(parts("2025-01-01", "FREQ=DAILY")) == Err(Malformed("DTSTART")) and
				status(parts("20250101", "FREQ=DAILY;UNTIL=20250131T000000Z")) == Err(Incompatible("DATE-TIME with DATE")) and
					status(parts("20250101", "FREQ=DAILY;UNTIL=T")) == Err(Malformed("UNTIL")) and
						status({ ..parts("20250101", "FREQ=DAILY"), exclusions: ["20250230"] }) == Err(InvalidDate("EXDATE"))
}

expect {
	status(parts("20250101", "FREQ=HOURLY")) == Err(Unsupported("subdaily DATE recurrence")) and
		status(parts("20250101", "FREQ=DAILY;BYHOUR=12")) == Err(Incompatible("clock selector with DATE")) and
			status(parts("20250101", "FREQ=YEARLY;RSCALE=HEBREW")) == Err(Unsupported("RSCALE")) and
				status(parts("20250101", "FREQ=DAILY;X-SKIP=FORWARD")) == Err(Unsupported("X-SKIP"))
}

expect {
	status(parts("20250101", "FREQ=YEARLY;BYMONTHDAY=1")) == Err(Unsupported("YEARLY BYMONTHDAY requires explicit BYMONTH in this profile")) and
		status(parts("20250101", "FREQ=YEARLY;BYWEEKNO=1")) == Err(Unsupported("YEARLY BYWEEKNO requires explicit BYDAY in this profile")) and
			status(parts("20250120", "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-1")) == Err(InvalidRule(UnsynchronizedStart)) and
				status(parts("20250101", "FREQ=WEEKLY;BYMONTHDAY=1")) == Err(InvalidRule(InvalidCombination("BYMONTHDAY with WEEKLY")))
}

expect {
	status(parts("20250101", Str.repeat("x", 65537))) == Err(TooLarge) and
		status({ ..parts("20250101", "FREQ=DAILY"), inclusions: List.repeat("20250101", 4097) }) == Err(TooLarge) and
			status(parts("20250101", "FREQ=DAILY;BYMONTH=${Str.join_with(List.repeat("1", 4097), ",")}")) == Err(TooLarge)
}
