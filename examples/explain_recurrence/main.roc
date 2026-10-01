app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import SeriesReview

main! = |_| {
	reports = SeriesReview.review(
		{ start: "20250131", rule: "FREQ=MONTHLY;COUNT=1", inclusions: ["20250704"], exclusions: ["20250131"] },
		{ start: "20261001T090000", rule: "FREQ=WEEKLY;BYDAY=TH", duration: "PT1H", inclusions: [], exclusions: [], periods: [], mode: Zoned },
	)?
	for item in reports {
		echo!("${item.title} (rendering ${Str.inspect(item.report.status)})\n${item.report.text}\n")
	}
	Ok({})
}
