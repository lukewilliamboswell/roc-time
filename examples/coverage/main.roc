app [main!] {
	time: "../../package/main.roc",
}

import Availability
import time.CalendarDate
import time.ClockTime
import time.FixedOffset
import time.LocalDateTime

main! = |_args| {
	date = CalendarDate.from_fields(Gregorian, { year: 2026, month: 6, day: 15 })?
	local = |hour, minute| {
		clock = ClockTime.from_fields({ hour, minute, second: 0, microsecond: 0 })?
		Ok(LocalDateTime.new(date, clock))
	}
	utc = FixedOffset.from_seconds(0)
	# The first booking supplies +02:00 explicitly; no city rules are inferred.
	available = Availability.from_bookings(
		{ start: local(9, 0)?, end: local(17, 0)?, offset: utc },
		[
			{ start: local(12, 0)?, end: local(13, 0)?, offset: FixedOffset.from_seconds(7200) },
			{ start: local(10, 30)?, end: local(12, 0)?, offset: utc },
		],
	)?
	echo!("Room availability on 2026-06-15\n")
	echo!("Opening: 09:00–17:00 UTC; bookings: 12:00–13:00 +02:00 and 10:30–12:00 UTC\n")
	for line in Availability.report(available)? {
		echo!("${line}\n")
	}
	Ok({})
}
