app [main!] {
	time: "../../package/main.roc",
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
