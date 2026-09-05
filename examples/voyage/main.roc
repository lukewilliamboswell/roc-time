app [main!] {
	time: "../../package/main.roc",
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
