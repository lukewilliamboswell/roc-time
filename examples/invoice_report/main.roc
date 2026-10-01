app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
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
