app [main!] { time: "../../../package/main.roc" }
import time.CalendarValue
import time.EnglishGregorian

main! = |_args| {
	year = CalendarValue.year(Gregorian, 2026)?
	_ = EnglishGregorian.date(year)
	Ok({})
}
