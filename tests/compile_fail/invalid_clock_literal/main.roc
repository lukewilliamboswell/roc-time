app [main!] { time: "../../../package/main.roc" }
import time.ClockTime

main! = |_args| {
	clock : ClockTime
	clock = "23:59:60"
	_ = clock
	Ok({})
}
