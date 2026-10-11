app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-tzdb-Ew1nW7PzcwxnidgmDydRHnYyQRB4sjq2dD7H2DDpsyMj.tar.zst",
}
import zones.Database
import time.ZoneRules
import Staffing

main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	shift = Staffing.overnight(rules, "2026-10-03", "2026-10-04")?
	echo!(Staffing.report(shift))
	Ok({})
}
