app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
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
