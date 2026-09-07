app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
	zones: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-tzdb-FgMq4S7KKindobxXL7PrFNnbmMqavB4h8ehZKCzE9VGC.tar.zst",
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
