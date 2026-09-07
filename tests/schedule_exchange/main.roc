app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import ScheduleExchange

main! = |_args| {
	for line in ScheduleExchange.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
