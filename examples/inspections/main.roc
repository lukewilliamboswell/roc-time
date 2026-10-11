app [main!] {
	time: "../../package/main.roc",
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
