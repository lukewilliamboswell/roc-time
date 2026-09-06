app [main!] {
	time: "../../package/main.roc",
}
import CivilArchive
import time.RfcDateTime

main! = |_| {
	start : RfcDateTime
	start = "19700101T003000"
	end : RfcDateTime
	end = "19700101T004500"
	report = CivilArchive.review(start, end)?
	echo!(report)
	Ok({})
}
