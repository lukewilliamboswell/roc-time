app [main!] { time: "../../../package/main.roc" }
import time.NanoClockTime

main! = |_args| {
	clock : NanoClockTime
	clock = "12:00:00.1234567891"
	_ = clock
	Ok({})
}
