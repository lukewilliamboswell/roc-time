import time.RfcDateTime
import time.ZoneRules
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.ResolvedBoundary
import time.ResolvedSelection
import time.Explanation

## Review an appointment choice and a selection that crosses a synthetic fold.
## Explanation reads immutable results; resumption is an explicit separate step.
SelectionReview :: [].{
	review = |start, end| {
		if RfcDateTime.form(start) != Local or RfcDateTime.form(end) != Local {
			return Err(ExpectedLocalLabels)
		}
		validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(86400000000))?
		rules = ZoneRules.new_bounded("Synthetic/Fallback", "example-v1", validity, FixedOffset.from_seconds(3600), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(0) }], { minimum: 0, maximum: 3600 })?
		local = RfcDateTime.local_label(start)
		appointment = ResolvedBoundary.resolve(rules, local, Last)?
		cursor = ZoneRules.selection_cursor(rules, local, RfcDateTime.local_label(end))?
		paused = ResolvedSelection.collect(cursor, { max_segments: 1, max_members: 2 })?
		remaining = match paused.status {
			Limited(progress) => progress.cursor
			Complete(_) => return Err(ExpectedSecondSegment)
		}
		finished = ResolvedSelection.collect(remaining, { max_segments: 1, max_members: 2 })?
		Ok([
			explain("Appointment: choose the later occurrence", ResolvedBoundary(appointment)),
			explain("Selection: first evaluation step", SelectionBatch(paused)),
			explain("Selection: resumed evaluation", SelectionBatch(finished)),
		])
	}
}

explain = |title, source| {
	title,
	output: Explanation.plain(Explanation.new(source), { max_facts: 8, max_utf8_bytes: 4096 }),
}
