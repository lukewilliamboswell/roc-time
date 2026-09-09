app [main!] {
	roc: "nightly-2026-09-05-b195f5b",
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0/roc-time-6gt2mALoAXMVKcQvCpdisfaAU3S9XVdV3vR2CNA7e43t.tar.zst",
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
