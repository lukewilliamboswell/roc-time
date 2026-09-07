app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
}
import EventTerms

main! = |_| {
	reports = EventTerms.review(
		["P1D", "PT24H"],
		["20261003T120000/P1D", "20261003T120000Z/PT24H"],
		"2026-10-03T12:00:00+10:00/2026-10-04T12:00:00+11:00",
	)?
	for item in reports {
		echo!("${item.label} (${Str.inspect(item.report.status)})\n${item.report.text}\n")
	}
	Ok({})
}
