app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import BookingExchange

main! = |_args| {
	free = BookingExchange.available(
		"2026-06-15T09:00:00Z/2026-06-15T17:00:00Z",
		[
			"2026-06-15T12:00:00+02:00/2026-06-15T14:00:00+02:00",
			"2026-06-15T15:00:00Z/2026-06-15T16:00:00Z",
		],
	)?
	echo!("Restored available booking windows (UTC)\n")
	for text in free {
		echo!("${text}\n")
	}
	Ok({})
}
