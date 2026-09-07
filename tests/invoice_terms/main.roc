app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
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
