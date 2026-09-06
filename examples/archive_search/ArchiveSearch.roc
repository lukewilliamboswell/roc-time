import time.CalendarDate
import time.CalendarValue
import time.QualifiedCalendarValue
import time.RfcDateTime
import time.FixedOffset
import time.PosixSpan
import time.PosixBoundary
import time.ZoneRules
import time.Coverage

## Search by supplied calendar precision while retaining exact recording times.
ArchiveSearch :: [].{
	find = |date_fields, recording_times| {
		date = CalendarDate.from_fields(Gregorian, date_fields)?
		minute = CalendarValue.minute(date, 9, 30)?
		second = CalendarValue.second(date, 9, 30, 0)?
		validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
		rules = ZoneRules.new_bounded("Archive/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
		var recordings = []
		for text in recording_times {
			timestamp = match RfcDateTime.parse(text) {
				Ok(value) => value
				Err(error) => return Err(Timestamp(error))
			}
			recordings = recordings.append(RfcDateTime.utc_boundary(timestamp)?)
		}
		exact_minute = QualifiedCalendarValue.new(minute, [])?
		exact_second = QualifiedCalendarValue.new(second, [])?
		approximate = QualifiedCalendarValue.new(minute, [{ scope: Whole, qualifier: Approximate }])?
		var results = []
		for query in [{ label: "09:30 (minute)", value: exact_minute }, { label: "09:30:00 (second)", value: exact_second }, { label: "Around 09:30", value: approximate }] {
			outcome = count_matches(query.value, rules, recordings)?
			results = results.append({ label: query.label, outcome })
		}
		Ok(results)
	}
}

count_matches = |query, rules, recordings| {

	cursor = match QualifiedCalendarValue.selection_cursor(query, rules) {
		Ok(value) => value
		Err(NeedsModel) => return Ok(NeedsModel)
		Err(error) => return Err(error)
	}
	batch = ZoneRules.SelectionCursor.collect(cursor, { max_segments: 1, max_members: 1 })?
	coverage = match batch.status {
		Complete(value) => value
		Limited(_) => return Err(SearchIncomplete)
	}
	count = recordings.fold(
		0.U64,
		|n, point| if Coverage.contains(coverage, point) {
			n + 1
		} else {
			n
		},
	)
	Ok(Matches(count))
}
