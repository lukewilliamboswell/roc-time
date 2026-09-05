app [main!] { time: "../../../package/main.roc" }
import time.CivilDay
import time.PosixBoundary
main! = |_args| {
	_invalid = CivilDay.from_day_number(0) < PosixBoundary.from_microseconds(0)
	Ok({})
}
