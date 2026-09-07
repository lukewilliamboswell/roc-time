app [main!] { time: "../../../package/main.roc" }
import time.Calendar
import time.QualifiedCalendarValue
import time.CalendarEvidence
import time.Coverage
import time.PosixBoundary
main! = |_args| {
	value = Calendar.Value.year(Gregorian, 1970)?
	description = QualifiedCalendarValue.new(value, [{ scope: Whole, qualifier: Uncertain }])?
	alternatives = CalendarEvidence.new(description, [value])?
	_invalid = Coverage.contains(alternatives, PosixBoundary.from_microseconds(0))
	Ok({})
}
