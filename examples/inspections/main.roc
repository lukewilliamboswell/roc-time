app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import InspectionDates
main! = |_args| {
	dates = InspectionDates.for_year(2026)?
	echo!("Equipment inspection dates for 2026\nLast Tuesday every three months, starting in February.\n")
	for date in dates {
		echo!("${InspectionDates.display(date)}\n")
	}
	Ok({})
}
