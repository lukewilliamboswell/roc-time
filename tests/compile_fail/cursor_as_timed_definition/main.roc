app [main!] { time: "../../../package/main.roc" }
import time.ICalTimedRule
import time.LocalDateTime

main! = |_args| {
	rule = timed_parse({ start: "20250101T090000Z", rule: "FREQ=DAILY", duration: "PT1H", inclusions: [], exclusions: [], periods: [], mode: Utc })?
	start = local("2025-01-01T00:00")?
	end = local("2026-01-01T00:00")?
	cursor = ICalTimedRule.schedule(1.U64, rule, { start, end }, Utc)?
	_ = ICalTimedRule.to_parts(cursor)
	Ok({})
}

local = |text| match LocalDateTime.parse_gregorian(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(LocalInput(error))
}

timed_parse = |parts| match ICalTimedRule.parse(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(TimedParse(error))
}
