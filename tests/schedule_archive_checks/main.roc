app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import ScheduleArchiveChecks
main! = |args| {
	ScheduleArchiveChecks.run(args.get(0) ?? "")?
	echo!("PASS schedule archive identity, context and native-range checks\n")
	Ok({})
}
