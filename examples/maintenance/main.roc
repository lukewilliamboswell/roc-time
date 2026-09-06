app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-tzdb-5xpCNbPVbrBRi2GC7kKEg91eQVjLQrkAb5F1FHy4THgD.tar.zst",
}
import MaintenanceDates
import time.GregorianDate
import time.ZoneRules
import zones.Database
main! = |_args| {
	# Property values extracted from the service contractor's calendar.
	contract = { start: "20250131", rule: "FREQ=MONTHLY;COUNT=3", inclusions: ["20250415"], exclusions: ["20250331"] }
	start = GregorianDate.from_fields({ year: 2025, month: 4, day: 1 })?
	end = GregorianDate.from_fields({ year: 2025, month: 6, day: 1 })?
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	visits = MaintenanceDates.upcoming(contract, { start, end }, rules)?
	echo!("Service visits for April and May 2025\nThe March visit was moved to April 15; the original series still ends in May.\n")
	echo!("Full-day visits in Australia/Melbourne\n")
	for visit in visits {
		echo!(MaintenanceDates.report_visit(visit)?)
	}
	Ok({})
}
