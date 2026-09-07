app [main!] { time: "../../../package/main.roc" }
import time.GregorianDate

main! = |_args| {
	date : GregorianDate
	date = "1900-02-29"
	_ = date
	Ok({})
}
