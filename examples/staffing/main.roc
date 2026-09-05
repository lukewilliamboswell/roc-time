app [main!] {
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
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
