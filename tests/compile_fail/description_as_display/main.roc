app [main!] { time: "../../../package/main.roc" }
import time.Calendar
import time.EnglishGregorian

main! = |_args| {
	year = Calendar.Value.year(Gregorian, 2026)?
	_ = EnglishGregorian.date(year)
	Ok({})
}
