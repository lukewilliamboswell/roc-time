app [main!] {
	time: "https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc1/roc-time-2T6KR7B59FhCSNghyPAgP2j61YiU1F537CkB6UFUwzfY.tar.zst",
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
