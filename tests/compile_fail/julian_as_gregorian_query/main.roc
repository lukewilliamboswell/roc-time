app [main!] { time: "../../../package/main.roc" }
import time.JulianDate
import time.GregorianDate

main! = |_args| {
	date = JulianDate.from_fields({ year: 2021, month: 1, day: 1 })?
	_ = GregorianDate.iso_week_date(date)
	Ok({})
}
