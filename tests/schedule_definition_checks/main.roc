app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import ScheduleDefinitionChecks
main! = |args| {
	ScheduleDefinitionChecks.run(args.get(0) ?? "")?
	echo!("PASS schedule declaration identity, context and native-range checks\n")
	Ok({})
}
