app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import InvoiceReportChecks

main! = |args| {
	zero = U64.from_str(args.get(0) ?? "0") ?? 0
	InvoiceReportChecks.run(zero, args.get(1) ?? "")?
	echo!("PASS invoice report scenarios\n")
	Ok({})
}
