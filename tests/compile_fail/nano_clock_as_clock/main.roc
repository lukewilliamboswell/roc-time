app [main!] {
	time: "../../../package/main.roc",
}
import time.ClockTime
import time.Nanosecond.ClockTime as NanoClockTime

main! = |_args| {
	nano = NanoClockTime.from_nanoseconds_since_midnight(1)?
	_invalid = ClockTime.to_text(nano)
	Ok({})
}
