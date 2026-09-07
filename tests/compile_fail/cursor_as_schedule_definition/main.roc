app [main!] { time: "../../../package/main.roc" }
import time.ScheduleDefinition
import time.ICalTimedRule
import time.LocalDateTime

main! = |_args| {
	rule = ICalTimedRule.parse({ start: "19700101T000000Z", rule: "FREQ=DAILY", duration: "PT1H", mode: Utc, inclusions: [], exclusions: [], periods: [] }) ?? crash "valid fixture"
	saved = ScheduleDefinition.from_ical({ rule, context: Utc }) ?? crash "valid fixture"
	window = { start: LocalDateTime.parse_gregorian("1970-01-01T00:00") ?? crash "valid fixture", end: LocalDateTime.parse_gregorian("1970-01-03T00:00") ?? crash "valid fixture" }
	cursor = ScheduleDefinition.cursor(42.U64, saved, window) ?? crash "valid fixture"
	_ = ScheduleDefinition.definition(cursor)
	Ok({})
}
