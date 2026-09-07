app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
}
import MeetingExchange

main! = |_args| {
	for line in MeetingExchange.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
