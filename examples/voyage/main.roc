app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
}

import ShipClock
import Briefing
import time.ZoneRules
import time.CalendarDate
import time.ClockTime
import time.LocalDateTime

main! = |_args| {
	date = CalendarDate.from_fields(Gregorian, { year: 2026, month: 7, day: 1 })?
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
