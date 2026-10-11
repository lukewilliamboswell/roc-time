app [main!] {
	time: "../../package/main.roc",
}
import ScheduleDefinitionChecks
main! = |args| {
	ScheduleDefinitionChecks.run(args.get(0) ?? "")?
	echo!("PASS schedule declaration identity, context and native-range checks\n")
	Ok({})
}
