app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}

import Invoice

main! = |_args| {
	# An issued invoice has one calendar month of payment terms. This is a
	# civil due date; choosing a payment cutoff time and zone is a separate step.
	invoice = Invoice.with_monthly_terms({ year: 2025, month: 1, day: 31 }, 1)?
	echo!("Payment terms: one calendar month, clamped to month end\n")
	echo!(Invoice.report(invoice))
	Ok({})
}
