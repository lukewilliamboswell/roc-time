import InvoiceReport

## R05/R10/R14/R16: execute the actual application module, staged by the runner.
## These fixed accounting scenarios independently specify invoice identity,
## chronological ISO groups, checked totals and actionable parse failures.
## Runtime assertions remain active in optimized builds.
InvoiceReportChecks :: [].{
	run = |zero, suffix| {
		if zero != 0 or suffix != "" {
			crash "invoice fixtures require zero and empty suffix"
		}
		for fixture in [
			{ text: "not-a-date", error: Malformed },
			{ text: "2021-02-29", error: InvalidDay },
			{ text: "2021-13-01", error: InvalidMonth },
			{ text: "+2147483648-01-01", error: OutOfRange },
		] {
			result = InvoiceReport.render([
				{ id: "valid", date: "2021-01-01", cents: zero },
				{ id: "bad-invoice${suffix}", date: fixture.text, cents: zero },
			])
			if result != Err(InvalidInvoiceDate("bad-invoice", fixture.error)) {
				crash "invoice date failure lost its category or invoice ID"
			}
		}
		if InvoiceReport.render([
			{ id: "maximum", date: "2020-12-31", cents: U64.highest - zero },
			{ id: "one-more", date: "2021-01-01", cents: 1 },
		]) != Err(TotalOutOfRange) {
			crash "same ISO week overflow was hidden across calendar year boundary"
		}
		empty : List(InvoiceReport.Input)
		empty = []
		if InvoiceReport.render(empty) != Ok([
			"Invoice report (USD; supplied accounting dates)",
			"Totals by ISO week (week year, not calendar year)",
			"No invoices",
		]) {
			crash "empty invoice report"
		}
		result = InvoiceReport.render([
			{ id: "later", date: "2022-01-03", cents: 100 + zero },
			{ id: "first", date: "2021-01-01", cents: 200 },
			{ id: "earlier", date: "2021-01-04", cents: 300 },
			{ id: "duplicate-date", date: "2021-01-01", cents: 400 },
		])?
		if result != [
			"Invoice report (USD; supplied accounting dates)",
			"later: 3 Jan 2022 (Monday, day 3) | 2022-W01 | USD 1.00",
			"first: 1 Jan 2021 (Friday, day 1) | 2020-W53 | USD 2.00",
			"earlier: 4 Jan 2021 (Monday, day 4) | 2021-W01 | USD 3.00",
			"duplicate-date: 1 Jan 2021 (Friday, day 1) | 2020-W53 | USD 4.00",
			"Totals by ISO week (week year, not calendar year)",
			"2020-W53: USD 6.00",
			"2021-W01: USD 3.00",
			"2022-W01: USD 1.00",
		] {
			crash "invoice identity, input order or chronological week grouping changed"
		}
		Ok({})
	}
}
