app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-tzdb-5xpCNbPVbrBRi2GC7kKEg91eQVjLQrkAb5F1FHy4THgD.tar.zst",
}
import zones.Database
import time.ZoneRules
import Staffing

main! = |_args| {
	data = Database.get("Australia/Melbourne")?
	rules = ZoneRules.from_database(data)?
	shift = Staffing.overnight(rules, { year: 2026, month: 10, day: 3 }, { year: 2026, month: 10, day: 4 })?
	echo!(Staffing.report(shift))
	Ok({})
}
