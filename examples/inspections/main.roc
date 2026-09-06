app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
