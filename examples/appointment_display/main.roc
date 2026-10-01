app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import AppointmentDisplay

main! = |_args| {
	lines = AppointmentDisplay.describe("2026-09-07T09:30", "2026-09-07T09:30:00.125")?
	for line in lines {
		echo!("${line}\n")
	}
	Ok({})
}
