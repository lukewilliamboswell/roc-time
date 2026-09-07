app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
}
import InvoiceReport

main! = |_args| {
	invoices = [
		{ id: "INV-100", date: "2020-12-31", cents: 12500.U64 },
		{ id: "INV-101", date: "2021-01-01", cents: 7500 },
		{ id: "INV-102", date: "2021-01-01", cents: 2500 },
		{ id: "INV-103", date: "2021-01-04", cents: 9000 },
	]
	for line in InvoiceReport.render(invoices)? {
		echo!("${line}\n")
	}
	Ok({})
}
