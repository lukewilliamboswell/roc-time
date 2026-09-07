app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst",
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
