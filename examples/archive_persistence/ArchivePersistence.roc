import time.EdtfDate
import time.OffsetTimestamp
import time.PosixBoundary
import time.Persistence

## Preserve an uncertain catalogue date independently of its recording instant.
ArchivePersistence :: [].{
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
		date_document = Persistence.to_text(Persistence.new(EdtfDate(date)))
		timestamp_document = Persistence.to_text(Persistence.new(OffsetTimestamp(timestamp)))
		boundary_document = Persistence.to_text(Persistence.new(PosixBoundary(boundary)))
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
