app [main!] {
	roc: "nightly-2026-09-06-d85e877",
	time: "../../package/main.roc",
	zones: "../../tzdb/package/main.roc",
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
