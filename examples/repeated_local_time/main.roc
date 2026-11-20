app [main!] {
	time: "../../package/main.roc",
}
import RepeatedLocalTime
import time.ICalendar.DateTime as ICalDateTime

main! = |_| {
	start = "19700101T003000"
	end = "19700101T004500"
	report = RepeatedLocalTime.review(start, end)?
	echo!(report)
	Ok({})
}
