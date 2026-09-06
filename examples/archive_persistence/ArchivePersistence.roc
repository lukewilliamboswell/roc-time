import time.EdtfDate
import time.OffsetTimestamp
import time.PosixBoundary
import time.Persistence
import time.Calendar
import time.CalendarDate
import time.CalendarValue
import time.QualifiedCalendarValue
import time.LocalDateTime

## Preserve an uncertain catalogue date independently of its recording instant.
ArchivePersistence :: [].{

	## A diary's Julian calendar and supplied minute precision are part of its
	## description. Saving it must not invent a zone or interpret its uncertainty.
	historical = |calendar, fields, hour, minute, qualifications| {
		date = CalendarDate.from_fields(calendar, fields)?
		minute_value = CalendarValue.minute(date, hour, minute)?
		description = QualifiedCalendarValue.new(minute_value, qualifications)?
		document = Persistence.to_text(Persistence.new(QualifiedCalendarValue(description))?)
		restored = restore(document)?
		match restored {
			QualifiedCalendarValue(value) => {
				supplied = QualifiedCalendarValue.described_value(value)
				restored_date = LocalDateTime.date(CalendarValue.start_label(supplied))
				parts = CalendarDate.to_fields(restored_date)
				Ok({
					date: "${Calendar.to_name(CalendarDate.calendar(restored_date))} ${parts.year.to_str()}-${parts.month.to_str()}-${parts.day.to_str()}",
					resolution: Str.inspect(CalendarValue.resolution(supplied)),
					qualifications: Str.inspect(QualifiedCalendarValue.qualifications(value)),
				})
			}
			_ => Err(UnexpectedDocumentKind)
		}
	}

	save_and_restore = |date_text, timestamp_text| {
		date = match EdtfDate.parse(date_text) {
			Ok(value) => value
			Err(error) => return Err(Date(error))
		}
		timestamp = match OffsetTimestamp.parse(timestamp_text) {
			Ok(value) => value
			Err(error) => return Err(Timestamp(error))
		}
		boundary = OffsetTimestamp.boundary(timestamp)?
		# These documents can be saved by the application. Each carries its own
		# version and semantic profile; no zone lookup is needed to restore it.
		date_document = Persistence.to_text(Persistence.new(EdtfDate(date))?)
		timestamp_document = Persistence.to_text(Persistence.new(OffsetTimestamp(timestamp))?)
		boundary_document = Persistence.to_text(Persistence.new(PosixBoundary(boundary))?)
		restored_date = restore(date_document)?
		restored_timestamp = restore(timestamp_document)?
		restored_boundary = restore(boundary_document)?
		match (restored_date, restored_timestamp, restored_boundary) {
			(EdtfDate(d), OffsetTimestamp(t), PosixBoundary(p)) => Ok({
				date: EdtfDate.to_text(d),
				timestamp: OffsetTimestamp.to_text(t),
				coordinate: PosixBoundary.to_microseconds(p).to_str(),
			})
			_ => Err(UnexpectedDocumentKind)
		}
	}

	restore = |document| match Persistence.parse(document) {
		Ok(value) => Ok(Persistence.value(value))
		Err(error) => Err(Document(error))
	}
}
