app [main!] {
	time: "../../package/main.roc",
}
import MaintenanceDates
import time.GregorianDate
main! = |_args| {
	# Property values extracted from the service contractor's calendar.
	contract = { start: "20250131", rule: "FREQ=MONTHLY;COUNT=3", inclusions: ["20250415"], exclusions: ["20250331"] }
	start = GregorianDate.from_fields({ year: 2025, month: 4, day: 1 })?
	end = GregorianDate.from_fields({ year: 2025, month: 6, day: 1 })?
	dates = MaintenanceDates.upcoming(contract, { start, end })?
	echo!("Service visits for April and May 2025\nThe March visit was moved to April 15; the original series still ends in May.\n")
	for date in dates {
		echo!("${MaintenanceDates.display(date)}\n")
	}
	Ok({})
}
