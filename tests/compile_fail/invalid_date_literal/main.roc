app [main!] { time: "../../../package/main.roc" }
import time.Interchange.EdtfDate as EdtfDate

main! = |_args| {
	date : EdtfDate
	date = "1900-02-29"
	_ = date
	Ok({})
}
