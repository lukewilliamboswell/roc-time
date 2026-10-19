app [main!] {
	time: "../../package/main.roc",
}
import DeadlineChecks

main! = |args| {
	zero = I128.from_str(args.get(1) ?? "0") ?? 0
	DeadlineChecks.run(zero, args.get(2) ?? "")?
	echo!("PASS clock deadline boundary and JSON checks\n")
	Ok({})
}
