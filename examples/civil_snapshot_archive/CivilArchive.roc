import time.RfcDateTime
import time.LocalDateTime
import time.ZoneRules
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.ResolvedBoundary
import time.ResolvedSelection
import time.Persistence
import time.OffsetTimestamp
import time.Coverage

## A synthetic backward clock jump repeats local labels for an hour.
## Archive both appointment choices and the full selection for later review.
CivilArchive :: [].{
	review = |start, end| {
		if RfcDateTime.form(start) != Local or RfcDateTime.form(end) != Local {
			return Err(ExpectedLocalLabels)
		}
		validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(86400000000))?
		rules = ZoneRules.new_bounded("Synthetic/Fallback", "example-v1", validity, FixedOffset.from_seconds(3600), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(0) }], { minimum: 0, maximum: 3600 })?
		local = RfcDateTime.local_label(start)
		first = ResolvedBoundary.resolve(rules, local, First)?
		last = ResolvedBoundary.resolve(rules, local, Last)?
		selected = ResolvedSelection.resolve(rules, local, RfcDateTime.local_label(end))?
		first_restored = restored_boundary(first)?
		last_restored = restored_boundary(last)?
		restored = match restore(ResolvedSelection(selected))? {
			ResolvedSelection(value) => value
			_ => return Err(UnexpectedArchiveKind)
		}
		coverage = ResolvedSelection.coverage(restored)
		var $lines = [
			"Synthetic fallback: archive a repeated local time",
			"Local range: ${RfcDateTime.to_text(start)}/${RfcDateTime.to_text(end)}",
			"First occurrence (restored): ${utc(ResolvedBoundary.boundary(first_restored))?}",
			"Last occurrence (restored): ${utc(ResolvedBoundary.boundary(last_restored))?}",
			"Selection restored as ${Coverage.member_count(coverage).to_str()} separate windows:",
		]
		for span in Coverage.to_spans(coverage) {
			$lines = $lines.append("${utc(PosixSpan.start(span))?}/${utc(PosixSpan.end(span))?}")
		}
		Ok(Str.join_with($lines, "\n"))
	}
}

restored_boundary = |snapshot| match restore(ResolvedBoundary(snapshot))? {
	ResolvedBoundary(value) => Ok(value)
	_ => Err(UnexpectedArchiveKind)
}

restore = |value| {
	encoded = match Persistence.new(value) {
		Ok(document) => Persistence.to_text(document)
		Err(error) => return Err(Store(error))
	}
	match Persistence.parse(encoded) {
		Ok(document) => Ok(Persistence.value(document))
		Err(error) => Err(Load(error))
	}
}

utc = |boundary| {
	value = match OffsetTimestamp.from_boundary(boundary, UnassertedUtc, 0) {
		Ok(timestamp) => timestamp
		Err(error) => return Err(Display(error))
	}
	Ok(OffsetTimestamp.to_text(value))
}
