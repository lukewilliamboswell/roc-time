import time.DateRecurrence
import time.GregorianDate
import time.RfcDateRule

## Exchange extracted RFC 5545 DATE property values, not an ICS document or a
## versioned native archive. This date-only schedule needs no clock or zone.
## Import/export work depends on the definition, not its occurrence count.
## Evaluation has a finite half-open window and explicit work/output limits.
ScheduleExchange :: [].{
	render = || {
		imported = import_parts({
			start: "20250131",
			rule: "FREQ=MONTHLY;COUNT=3",
			inclusions: [],
			exclusions: [],
		})?
		definition = DateRecurrence.definition(imported)
		added = parse_date("2025-07-04")?
		removed = parse_date("2025-03-31")?
		edited = DateRecurrence.new(
			definition.anchor,
			{
				..definition.spec,
				inclusions: definition.spec.inclusions.append(added),
				exclusions: definition.spec.exclusions.append(removed),
			},
		)?
		parts = match RfcDateRule.to_parts(edited) {
			Ok(value) => value
			Err(error) => return Err(Export(error))
		}
		restored = import_parts(parts)?
		start = parse_date("2025-01-01")?
		end = parse_date("2025-08-01")?
		cursor = DateRecurrence.cursor(restored, { start, end })?
		batch = DateRecurrence.Cursor.collect(
			cursor,
			{
				max_steps: 1000,
				max_buffered: 31,
				max_occurrences: 10,
			},
		)?
		var $lines = [
			"Date-only schedule exchange (extracted RFC property values)",
			"Imported: monthly on the 31st, COUNT=3",
			"Edited: exclude 31 March; add 4 July",
			"Canonical DTSTART value: ${parts.start}",
			"Canonical RRULE value: ${parts.rule}",
		]
		for value in parts.inclusions {
			$lines = $lines.append("Canonical RDATE value: ${value}")
		}
		for value in parts.exclusions {
			$lines = $lines.append("Canonical EXDATE value: ${value}")
		}
		$lines = $lines.append("Reimported dates in [2025-01-01, 2025-08-01):")
		for date in batch.dates {
			$lines = $lines.append(GregorianDate.to_text(date))
		}
		match batch.status {
			Complete => {
				$lines = $lines.append("Complete: missing month-days are skipped; exclusions do not replenish COUNT.")
			}
			Limited(progress) => {
				$lines = $lines.append("Partial results: ${limit_name(progress.reason)}; retain the returned cursor to resume.")
			}
		}
		Ok($lines)
	}
}

import_parts = |parts| match RfcDateRule.parse(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(Import(error))
}

limit_name = |reason| match reason {
	WorkLimit => "work budget reached"
	BufferLimit => "buffer budget reached"
	OutputLimit => "output budget reached"
}

parse_date = |text| match GregorianDate.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Date(error))
}
