import time.ICalDateTime
import time.LocalDateTime
import time.ZoneRules
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.ResolvedBoundary
import time.ResolvedSelection
import time.OffsetTimestamp
import time.Coverage

## A synthetic backward clock jump repeats local labels for an hour.
## Compare both appointment choices with the complete local selection.
RepeatedLocalTime :: [].{
	review = |start, end| {
		if ICalDateTime.form(start) != Local or ICalDateTime.form(end) != Local {
			return Err(ExpectedLocalLabels)
		}
		validity = PosixSpan.new({ start: PosixBoundary.from_microseconds(-86400000000), end: PosixBoundary.from_microseconds(86400000000) })?
		rules = ZoneRules.new_bounded({ name: "Synthetic/Fallback", version: "example-v1", validity, initial: FixedOffset.from_seconds(3600), transitions: [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(0) }], bounds: { minimum: 0, maximum: 3600 } })?
		local = ICalDateTime.local_label(start)
		first = ResolvedBoundary.resolve(rules, { local, occurrence: First })?
		last = ResolvedBoundary.resolve(rules, { local, occurrence: Last })?
		selected = ResolvedSelection.resolve(rules, { start: local, end: ICalDateTime.local_label(end) })?
		coverage = ResolvedSelection.coverage(selected)
		var $lines = [
			"Synthetic fallback: interpret a repeated local time",
			"Local range: ${ICalDateTime.to_text(start)}/${ICalDateTime.to_text(end)}",
			"First occurrence: ${utc(ResolvedBoundary.boundary(first))?}",
			"Last occurrence: ${utc(ResolvedBoundary.boundary(last))?}",
			"Selection contains ${Coverage.member_count(coverage).to_str()} separate windows:",
		]
		for span in Coverage.to_spans(coverage) {
			$lines = $lines.append("${utc(PosixSpan.start(span))?}/${utc(PosixSpan.end(span))?}")
		}
		Ok(Str.join_with($lines, "\n"))
	}
}

utc = |boundary| {
	value = match OffsetTimestamp.from_boundary(boundary, { offset: UnassertedUtc, fraction_digits: 0 }) {
		Ok(timestamp) => timestamp
		Err(error) => return Err(Display(error))
	}
	Ok(OffsetTimestamp.to_text(value))
}
