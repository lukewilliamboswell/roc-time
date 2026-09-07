app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import ScheduleArchive
main! = |_args| {
	for line in ScheduleArchive.render()? {
		echo!("${line}\n")
	}
	Ok({})
}
