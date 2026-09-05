app [main!] {
	time: "../../package/main.roc",
}

import Availability

main! = |_args| {
	# These inputs are already resolved POSIX seconds, not local clock readings.
	available = Availability.from_bookings(
		{ start: 32400.Dec, end: 61200.Dec },
		[{ start: 36000.Dec, end: 39600.Dec }, { start: 37800.Dec, end: 43200.Dec }],
	)?
	echo!("Room availability on 1970-01-01 (UTC)\n")
	echo!("Opening hours: 09:00–17:00; bookings: 10:00–11:00 and 10:30–12:00\n")
	for line in Availability.report(available)? {
		echo!("${line}\n")
	}
	Ok({})
}
