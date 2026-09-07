import time.EdtfDate
import time.OffsetTimestamp

## Store catalogue dates as EDTF and recording timestamps as RFC 3339.
CatalogueStorage :: [].{
	save_and_restore = |date_text, timestamp_text| {
		date = parse_date(date_text)?
		timestamp = parse_timestamp(timestamp_text)?
		# The application stores these strings in its own catalogue record.
		stored = { date: EdtfDate.to_text(date), recorded_at: OffsetTimestamp.to_text(timestamp) }
		restored_date = parse_date(stored.date)?
		restored_timestamp = parse_timestamp(stored.recorded_at)?
		Ok({ date: EdtfDate.to_text(restored_date), timestamp: OffsetTimestamp.to_text(restored_timestamp) })
	}
}

parse_date = |text| match EdtfDate.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Date(error))
}

parse_timestamp = |text| match OffsetTimestamp.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Timestamp(error))
}
