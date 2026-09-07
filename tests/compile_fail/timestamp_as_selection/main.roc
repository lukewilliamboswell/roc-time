app [main!] { time: "../../../package/main.roc" }
import time.LocalDateTime
import time.OffsetTimestamp
import time.Calendar
main! = |_| {
	value = parse("2026-06-15T12:30:00Z")?
	_ = LocalDateTime.calendar_value_bounds(value)
	Ok({})
}

parse = |text| match OffsetTimestamp.parse(text) {
	Ok(value) => Ok(value)
	Err(_) => Err(Exit(1))
}
