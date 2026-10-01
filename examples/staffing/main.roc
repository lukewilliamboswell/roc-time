app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-tzdb-3JTmpDV26cHNH7cN1HqHzUWTZKpyaYgLYkWSws8Tqj3e.tar.zst",
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
