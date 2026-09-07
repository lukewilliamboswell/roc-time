app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc2/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
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
