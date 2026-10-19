app [main!] {
	time: "../../package/main.roc",
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
