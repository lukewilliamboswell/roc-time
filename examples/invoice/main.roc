app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
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
