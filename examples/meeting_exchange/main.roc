app [main!] {
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
