app [main!] {
	roc: "nightly-2026-09-27-a3ce7f1",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.2.0-rc1/roc-time-GPETAiR4TeEPxDA1F6qHxbDnFexmj4tYgUrkEryBhtdP.tar.zst",
}
import SelectionReview
import time.ICalDateTime

main! = |_| {
	start = "19700101T003000"
	end = "19700101T004500"
	reports = SelectionReview.review(start, end)?
	for report in reports {
		echo!("${report.title} (rendering ${Str.inspect(report.output.status)})\n")
		echo!("${report.output.text}\n")
	}
	Ok({})
}
