app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-tzdb-Ew1nW7PzcwxnidgmDydRHnYyQRB4sjq2dD7H2DDpsyMj.tar.zst",
}
import DispatchDeadlines
import zones.Database
import time.ZoneRules
main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	start = DispatchDeadlines.midnight(2025, 3, 1)?
	end = DispatchDeadlines.midnight(2025, 5, 1)?
	deadlines = DispatchDeadlines.upcoming(rules, { start, end })?
	echo!("Remaining deadlines for the four-month dispatch contract\nFinal Monday, final pickup slot; March and April 2025\nJanuary waived; the original contract still ends in April.\n")
	for deadline in deadlines {
		match DispatchDeadlines.report(deadline) {
			Ok(text) => echo!(text)
			Err(_) => return Err(DisplayOutOfRange)
		}
	}
	Ok({})
}
