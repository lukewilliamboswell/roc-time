app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
}

import ShipClock
import Briefing
import time.ZoneRules
import time.Calendar
import time.ClockTime
import time.LocalDateTime

main! = |_args| {
	date = Calendar.Date.from_fields(Gregorian, { year: 2026, month: 7, day: 1 })?
	clock = ClockTime.from_fields({ hour: 12, minute: 0, second: 0, microsecond: 0 })?
	local = LocalDateTime.new(date, clock)
	original = ZoneRules.from_database(ShipClock.get("Voyage/Research", Published)?)?
	saved = Briefing.book(original, local)?
	updated = ZoneRules.from_database(ShipClock.get("Voyage/Research", Revised)?)?
	reviewed = Briefing.review(saved, updated)?
	# Explicit matching avoids the pinned interpreter's result-widening defect.
	report = match Briefing.report(reviewed) {
		Ok(value) => value
		Err(OutOfRange) => return Err(OutOfRange)
	}
	echo!(report)
	Ok({})
}
