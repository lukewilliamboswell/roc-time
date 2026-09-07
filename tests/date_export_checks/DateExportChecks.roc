import time.RfcDateRule
import time.DateRecurrence
import time.CalendarPattern
import time.GregorianDate
import time.CivilDay

# R11/R12/R14: source inputs only; independently authored expectations live
# outside this executable so neither canonical text nor occurrences are blessed.
DateExportChecks :: [].{
	run = |name| {
		if name == "exact-cap" {
			return exact_cap()
		}
		if name.starts_with("native-") {
			return native(name)
		}
		parts = match name {
			"monthly" => { start: "20250131", rule: "COUNT=3;FREQ=MONTHLY", inclusions: ["20250204,20250331", "20250204"], exclusions: ["20250331"] }
			"until" => { start: "20250101", rule: "UNTIL=20250103;FREQ=DAILY", inclusions: [], exclusions: [] }
			"wkst-mo" => { start: "19970805", rule: "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO", inclusions: [], exclusions: [] }
			"wkst-su" => { start: "19970805", rule: "FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=SU,TU;WKST=SU", inclusions: [], exclusions: [] }
			"last-weekday" => { start: "19970930", rule: "BYSETPOS=-1,-1;BYDAY=FR,MO,WE,TU,TH,MO;COUNT=3;FREQ=MONTHLY", inclusions: [], exclusions: [] }
			"forever" => { start: "20250101", rule: "FREQ=DAILY", inclusions: [], exclusions: [] }
			"count-max" => { start: "20250101", rule: "FREQ=DAILY;COUNT=2147483647", inclusions: [], exclusions: [] }
			"ordinal-extremes" => { start: "20180101", rule: "FREQ=YEARLY;COUNT=2;BYDAY=53SU,1MO,-53MO,MO,-53SU,1MO", inclusions: [], exclusions: [] }
			"week-numbers" => { start: "20200101", rule: "FREQ=YEARLY;COUNT=2;BYWEEKNO=1,-1,1;BYDAY=WE", inclusions: [], exclusions: [] }
			"year-days" => { start: "20250101", rule: "FREQ=YEARLY;COUNT=2;BYYEARDAY=1,-1,1", inclusions: [], exclusions: [] }
			"month-days" => { start: "20250101", rule: "FREQ=YEARLY;COUNT=4;BYMONTH=12,1,12;BYMONTHDAY=1,-1,1", inclusions: [], exclusions: [] }
			"set-positions" => { start: "20250106", rule: "FREQ=MONTHLY;COUNT=4;BYDAY=MO;BYSETPOS=1,-1,1", inclusions: [], exclusions: [] }
			_ => crash "Unknown date export fixture"
		}
		original = RfcDateRule.parse(parts) ?? crash "Fixture import rejected"
		definition = DateRecurrence.definition(original)
		rebuilt = DateRecurrence.new(definition.anchor, definition.spec) ?? crash "Definition reconstruction failed"
		exported = RfcDateRule.to_parts(rebuilt) ?? crash "Fixture export rejected"
		restored = RfcDateRule.parse(exported) ?? crash "Export cannot be imported"
		end = if name == "forever" or name == "count-max" {
			date(2025, 1, 4)
		} else if name == "ordinal-extremes" {
			date(2019, 1, 1)
		} else if name == "week-numbers" {
			date(2021, 1, 1)
		} else if name == "year-days" or name == "month-days" {
			date(2026, 1, 1)
		} else if name.starts_with("wkst") {
			date(1997, 9, 1)
		} else if name == "last-weekday" {
			date(1998, 1, 1)
		} else {
			date(2025, 6, 1)
		}
		first = collect(original, definition.anchor, end)
		second = collect(restored, definition.anchor, end)
		if first != second {
			crash "Export changed recurrence execution"
		}
		Json.to_str({ parts: exported, dates: first })
	}
}

date = |year, month, day| GregorianDate.from_fields({ year, month, day }) ?? crash "Invalid test date"

collect = |rule, start, end| {
	cursor = DateRecurrence.cursor(rule, { start, end }) ?? crash "Invalid test window"
	batch = DateRecurrence.Cursor.collect(cursor, { max_steps: 10000, max_buffered: 366, max_occurrences: 100 }) ?? crash "Fixture evaluation failed"
	match batch.status {
		Complete => {}
		Limited(_) => crash "Fixture evaluation incomplete"
	}
	batch.dates.map(GregorianDate.to_text)
}

native = |name| {
	anchor = if name == "native-start-zero" {
		date(0, 1, 1)
	} else if name == "native-start-high" {
		date(10000, 1, 1)
	} else {
		date(2025, 1, 1)
	}
	pattern = match name {
		"native-interval" => { ..CalendarPattern.defaults(Daily), interval: 2147483648 }
		"native-year-monthday" => { ..CalendarPattern.defaults(Yearly), by_month_day: [1] }
		"native-year-weekno" => { ..CalendarPattern.defaults(Yearly), by_week_no: [1] }
		_ => CalendarPattern.defaults(Daily)
	}
	termination = match name {
		"native-count" => Count(2147483648)
		"native-until-zero" => Until(date(0, 1, 2))
		"native-until-high" => Until(date(10000, 1, 1))
		_ => Forever
	}
	actual_anchor = if name == "native-until-zero" {
		date(-1, 1, 1)
	} else {
		anchor
	}
	inclusions = match name {
		"native-size" => many_dates()
		"native-rdate-zero" => [date(0, 1, 1)]
		"native-rdate-high" => [date(10000, 1, 1)]
		_ => []
	}
	exclusions = match name {
		"native-size" => many_dates()
		"native-exdate-zero" => [date(0, 1, 1)]
		"native-exdate-high" => [date(10000, 1, 1)]
		_ => []
	}
	positions = if name == "native-setpos" {
		[1.I16]
	} else {
		[]
	}
	rule = match DateRecurrence.new(actual_anchor, { pattern, termination, by_set_pos: positions, inclusions, exclusions }) {
		Ok(value) => value
		Err(error) => if name == "native-interval" {
			return Str.inspect(error)
		} else {
			crash "Native fixture rejected before export"
		}
	}
	match RfcDateRule.to_parts(rule) {
		Err(error) => Str.inspect(error)
		Ok(_) => crash "Native-only fixture unexpectedly exported"
	}
}

many_dates = || dates_with_count(4096)

dates_with_count = |count| {
	var $dates = []
	var $n = 0.I64
	while $n < count {
		$dates = $dates.append(GregorianDate.from_civil_day(CivilDay.from_day_number($n)) ?? crash "Fixture date range")
		$n = $n + 1
	}
	$dates
}

exact_cap = || {
	anchor = date(2025, 1, 1)
	spec = { pattern: { ..CalendarPattern.defaults(Daily), interval: 1234 }, termination: Forever, by_set_pos: [], inclusions: dates_with_count(4096), exclusions: dates_with_count(4091) }
	rule = DateRecurrence.new(anchor, spec) ?? crash "Exact cap construction"
	parts = RfcDateRule.to_parts(rule) ?? crash "Exact byte cap rejected"
	restored = RfcDateRule.parse(parts) ?? crash "Exact byte cap reimport rejected"
	if (RfcDateRule.to_parts(restored) ?? crash "Exact cap reexport") != parts {
		crash "Exact cap semantic text changed"
	}
	oversized = DateRecurrence.new(anchor, { ..spec, exclusions: dates_with_count(4092) }) ?? crash "Oversize construction"
	if RfcDateRule.to_parts(oversized) != Err(TooLarge) {
		crash "One entry above cap accepted"
	}
	var $bytes = parts.start.count_utf8_bytes() + parts.rule.count_utf8_bytes()
	for entry in parts.inclusions.concat(parts.exclusions) {
		$bytes = $bytes + entry.count_utf8_bytes()
	}
	Json.to_str({ bytes: $bytes, start: parts.start, rule: parts.rule, inclusions: parts.inclusions.len(), exclusions: parts.exclusions.len() })
}
