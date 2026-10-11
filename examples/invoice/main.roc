app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}

import Invoice

main! = |_args| {
	# An issued invoice has one calendar month of payment terms. This is a
	# civil due date; choosing a payment cutoff time and zone is a separate step.
	invoice = Invoice.with_monthly_terms("2025-01-31", 1)?
	echo!("Payment terms: one calendar month, clamped to month end\n")
	echo!(Invoice.report(invoice))
	Ok({})
}
