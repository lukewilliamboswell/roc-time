app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-tzdb-Ew1nW7PzcwxnidgmDydRHnYyQRB4sjq2dD7H2DDpsyMj.tar.zst",
}
import LoanSchedule
import zones.Database
import time.ZoneRules
main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	loans = LoanSchedule.upcoming(rules)?
	echo!("Equipment loans: monthly starts and one extra booking\nMonthly loans clamp to month end; the extra booking lasts one week. Melbourne local times.\n")
	for loan in loans {
		match LoanSchedule.report(loan) {
			Ok(text) => echo!(text)
			Err(_) => return Err(InvalidReport)
		}
	}
	Ok({})
}
