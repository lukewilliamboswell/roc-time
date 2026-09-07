app [main!] { time: "../../package/main.roc" }
import TimedExportChecks

main! = |args| {
	echo!("${TimedExportChecks.run(args)}\n")
	Ok({})
}
