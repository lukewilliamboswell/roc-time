import time.Calendar

## Preserve an archive's source calendar while displaying a common catalogue date.
ArchiveDate :: { original : Calendar.Date, catalogue : Calendar.Date }.{
	from_record : Str, Calendar.Date.Fields -> Try(ArchiveDate, [UnsupportedCalendar(Str), OutOfRange, InvalidMonth, InvalidDay, ..])
	from_record = |calendar_name, fields| {
		calendar = match Calendar.from_name(calendar_name) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		original = Calendar.Date.from_fields(calendar, fields)?
		catalogue = Calendar.Date.in_calendar(original, Gregorian)?
		Ok({ original, catalogue })
	}

	report : ArchiveDate -> Str
	report = |entry| {
		"Source record: ${display(entry.original)}\nCatalogue date: ${display(entry.catalogue)}\n"
	}
}

display = |date| {
	fields = Calendar.Date.to_fields(date)
	calendar = Calendar.to_name(Calendar.Date.calendar(date))
	"${fields.year.to_str()}-${fields.month.to_str()}-${fields.day.to_str()} (${calendar})"
}
