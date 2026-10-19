import time.EdtfInterval
import time.CalendarInterval

## Import catalog date ranges without inventing dates the archivist did not know.
ArchiveInterval := [].{
	import_record : Str, Str -> Try({ accession : Str, created : EdtfInterval }, EdtfInterval.Error)
	import_record = |accession, text| {
		created = EdtfInterval.parse(text)?
		Ok({ accession, created })
	}

	## Canonical standard text can be saved in an application-owned catalog row.
	export_record = |record| "${record.accession}: ${EdtfInterval.to_text(record.created)}"

	## Answer honestly when the application asks for exact timeline coverage.
	query_status = |record| match CalendarInterval.interpretation_support(EdtfInterval.description(record.created)) {
		UnsupportedCivilEndpointModel => "Exact timeline search needs an endpoint model; the catalog description is saved."
	}
}
