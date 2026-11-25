import time.Calendar
import time.Calendar.CivilDay as CivilDay
import time.ClockTime
import time.Coverage
import time.FixedOffset
import time.LocalDateTime
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules

ZoneAdmission := {}

# R01/R07/R12. The finite provider has one segment with the most negative
# I32 offset. Its advertised upper offset is one second larger and does
# not occur in the table. At local labels representing timeline L under
# the observed offset, an unseen occurrence would lie at L - 1 second.
# Changing only the label/validity by one microsecond distinguishes the
# signed axis limit from the provider's inclusive lower validity bound.
expect {
	actual = I32.lowest
	low = I64.lowest
	observation = low + 1000000
	validity = span(low, observation + 2)
	wide = rules(validity, actual, { minimum: actual, maximum: actual + 1 })
	tight = rules(validity, actual, { minimum: actual, maximum: actual })
	trimmed = rules(span(low + 1, observation + 2), actual, { minimum: actual, maximum: actual + 1 })
	for calendar in [Gregorian, Julian] {
		left = label(observation - 1, actual, calendar)
		edge = label(observation, actual, calendar)
		right = label(observation + 1, actual, calendar)
		if ZoneRules.resolve(tight, left) != Ok(Unique(point(observation - 1))) or
			ZoneRules.select(tight, { start: left, end: edge }) != Ok(Coverage.from_spans([span(observation - 1, observation)])) {
			crash "Lower-edge table must contain the visible preimage"
		}
		if !classification_error(wide, left, OutOfRange) or
			!selection_error(wide, { start: left, end: edge }, OutOfRange) {
			crash "The unseen lower candidate must report signed underflow"
		}
		if !classification_at(wide, edge, observation) or
			!selection_at(wide, { start: edge, end: right }, span(observation, observation + 1)) {
			crash "The inclusive earliest candidate must admit both queries"
		}
		if !classification_error(trimmed, edge, OutsideValidity) or
			!selection_error(trimmed, { start: edge, end: right }, OutsideValidity) {
			crash "The same representable candidate must reject narrower rules"
		}
	}
	True
}

# The other provider advertises an unseen offset one second below its
# positive actual offset. Its unseen candidate lies at L + 1 second.
# The classification at the exclusive upper boundary must fail. Using
# that label as the selection's excluded end is complete and yields a
# single-microsecond span. Shortening the provider by a microsecond makes
# that same selection incomplete, and shifting the end by a microsecond
# takes the unseen candidate off the signed axis entirely.
expect {
	actual = I32.highest
	high = I64.highest
	observation = high - 1000000
	validity = span(observation - 2, high)
	wide = rules(validity, actual, { minimum: actual - 1, maximum: actual })
	tight = rules(validity, actual, { minimum: actual, maximum: actual })
	trimmed = rules(span(observation - 2, high - 1), actual, { minimum: actual - 1, maximum: actual })
	for calendar in [Gregorian, Julian] {
		left = label(observation - 1, actual, calendar)
		edge = label(observation, actual, calendar)
		right = label(observation + 1, actual, calendar)
		if ZoneRules.resolve(tight, edge) != Ok(Unique(point(observation))) or
			ZoneRules.resolve(tight, right) != Ok(Unique(point(observation + 1))) {
			crash "Upper-edge table must contain the visible preimages"
		}
		if !classification_at(wide, left, observation - 1) or !classification_error(wide, edge, OutsideValidity) or
			!classification_error(wide, right, OutOfRange) {
			crash "The upper candidate is inclusive for classification"
		}
		selection = { start: left, end: edge }
		if !selection_at(wide, selection, span(observation - 1, observation)) or
			!selection_error(trimmed, selection, OutsideValidity) or
				!selection_error(wide, { start: edge, end: right }, OutOfRange) {
			crash "The latest possible selection end is exclusive"
		}
	}
	True
}

point = PosixBoundary.from_microseconds

span = |start, end| PosixSpan.new({ start: point(start), end: point(end) }) ?? crash "nonempty validity fixture"

rules = |validity, actual, bounds| ZoneRules.Provider.new_bounded({
	name: "Synthetic/SignedAdmission",
	version: "v1",
	validity,
	initial: FixedOffset.from_seconds(actual),
	bounds,
	transitions: [],
}) ?? crash "valid synthetic rules"

# Widen the local fixture coordinate independently of FixedOffset, since
# the actual civil coordinates are beyond the signed POSIX range. Use the
# public civil axis solely to construct the equivalent date description.
label : I64, I32, Calendar -> LocalDateTime
label = |coordinate, actual, calendar| {
	local = coordinate.to_i128() + actual.to_i128() * 1000000
	day = I128.div_floor_by(local, 86400000000)
	clock_micros = local - day * 86400000000
	day_number = I128.to_i64_try(day) ?? crash "fixture day fits I64"
	micros = I128.to_i64_try(clock_micros) ?? crash "fixture clock fits I64"
	date = Calendar.Date.from_civil_day(calendar, CivilDay.from_day_number(day_number)) ?? crash "fixture civil day"
	clock = ClockTime.from_microseconds_since_midnight(micros) ?? crash "fixture clock"
	LocalDateTime.new({ date, clock })
}

classification_error = |rules_value, local, expected| {
	ZoneRules.resolve(rules_value, local) == Err(expected) and match ZoneRules.ClassificationCursor.from_local(rules_value, local) {
		Err(error) => error == expected
		Ok(_) => False
	}
}

classification_at = |rules_value, local, coordinate| {
	expected = Unique(point(coordinate))
	cursor = ZoneRules.ClassificationCursor.from_local(rules_value, local) ?? crash "admitted classification"
	batch = ZoneRules.ClassificationCursor.collect(cursor, { max_segments: 1, max_candidates: 1 }) ?? crash "bounded classification"
	ZoneRules.resolve(rules_value, local) == Ok(expected) and batch.segments == 1 and batch.buffered == 1 and match batch.status {
		Complete(classification) => ZoneRules.Classification.resolution(classification) == expected
		Limited(_) => False
	}
}

selection_error = |rules_value, window, expected| {
	ZoneRules.select(rules_value, window) == Err(expected) and match ZoneRules.SelectionCursor.from_bounds(rules_value, window) {
		Err(error) => error == expected
		Ok(_) => False
	}
}

selection_at = |rules_value, window, expected_span| {
	expected = Coverage.from_spans([expected_span])
	cursor = ZoneRules.SelectionCursor.from_bounds(rules_value, window) ?? crash "admitted selection"
	batch = ZoneRules.SelectionCursor.collect(cursor, { max_segments: 1, max_members: 1 }) ?? crash "bounded selection"
	ZoneRules.select(rules_value, window) == Ok(expected) and batch.segments == 1 and batch.buffered == 1 and match batch.status {
		Complete(coverage) => coverage == expected
		Limited(_) => False
	}
}
