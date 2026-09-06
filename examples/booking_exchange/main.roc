app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
