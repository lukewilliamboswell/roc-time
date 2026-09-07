app [main!] { time: "../../package/main.roc" }
import DateExportChecks

main! = |args| {
	result = DateExportChecks.run(args.get(0) ?? "monthly")
	echo!("${result}\n")
	Ok({})
}
