import time.Calendar
import time.CalendarDate

## Preserve an archive's source calendar while displaying a common catalogue date.
ArchiveDate :: { original : CalendarDate, catalogue : CalendarDate }.{
	from_record : Str, CalendarDate.Fields -> Try(ArchiveDate, [UnsupportedCalendar(Str), OutOfRange, InvalidMonth, InvalidDay, ..])
	from_record = |calendar_name, fields| {
		calendar = match Calendar.from_name(calendar_name) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		original = CalendarDate.from_fields(calendar, fields)?
		catalogue = CalendarDate.in_calendar(original, Gregorian)?
		Ok({ original, catalogue })
	}

	report : ArchiveDate -> Str
	report = |entry| {
		"Source record: ${display(entry.original)}\nCatalogue date: ${display(entry.catalogue)}\n"
	}
}

display = |date| {
	fields = CalendarDate.to_fields(date)
	calendar = Calendar.to_name(CalendarDate.calendar(date))
	"${fields.year.to_str()}-${fields.month.to_str()}-${fields.day.to_str()} (${calendar})"
}
