app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
