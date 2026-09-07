import time.RfcDateTime
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
		if RfcDateTime.form(start) != Local or RfcDateTime.form(end) != Local {
			return Err(ExpectedLocalLabels)
		}
		validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(86400000000))?
		rules = ZoneRules.new_bounded("Synthetic/Fallback", "example-v1", validity, FixedOffset.from_seconds(3600), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(0) }], { minimum: 0, maximum: 3600 })?
		local = RfcDateTime.local_label(start)
		first = ResolvedBoundary.resolve(rules, local, First)?
		last = ResolvedBoundary.resolve(rules, local, Last)?
		selected = ResolvedSelection.resolve(rules, local, RfcDateTime.local_label(end))?
		coverage = ResolvedSelection.coverage(selected)
		var $lines = [
			"Synthetic fallback: interpret a repeated local time",
			"Local range: ${RfcDateTime.to_text(start)}/${RfcDateTime.to_text(end)}",
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
	value = match OffsetTimestamp.from_boundary(boundary, UnassertedUtc, 0) {
		Ok(timestamp) => timestamp
		Err(error) => return Err(Display(error))
	}
	Ok(OffsetTimestamp.to_text(value))
}
