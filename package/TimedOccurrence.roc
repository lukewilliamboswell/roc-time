import TimedRecurrence
import CalendarPattern
import ClockTime
import FixedOffset
import CalendarArithmetic
import CalendarDelta
import CalendarDate
import GregorianDate
import LocalDateTime
import PosixBoundary
import PosixDelta
import PosixSpan
import ZoneRules

## An identified nonempty appointment span derived from a timed source.
## Coordinate duration is a POSIX displacement, not physical SI elapsed time.
## Calendar duration advances the original Gregorian source label, resolves
## that calendar anchor with explicit policies, then adds its coordinate tail.
## Zero calendar movement retains the selected start without another lookup.
## A coordinate tail may extend beyond zone-data validity: it performs checked
## POSIX arithmetic and makes no claim about the final local clock label.
## It does not construct the preimage of every civil label between endpoints.
TimedOccurrence(id) :: { id : id, start : TimedRecurrence.Occurrence, duration : Duration, span : PosixSpan, calendar_anchor : [None, Some({ source : LocalDateTime, choice : ZoneRules.BoundaryChoice })] }.{
	Duration : [Coordinate(PosixDelta), Calendar(CalendarDuration)]
	CalendarDuration : { delta : CalendarDelta, invalid_date : CalendarArithmetic.Policy, tail : PosixDelta, occurrence : ZoneRules.OccurrencePolicy, gap : [RejectGap, UseOffsetBeforeGap] }
	Batch(id) : { segments : U64, buffered : U64, status : [Complete(TimedOccurrence(id)), Limited({ cursor : Cursor(id), reason : [WorkLimit, BufferLimit] })] }

	## Validate the duration's component domain without interpreting an anchor.
	validate_duration : Duration -> Try({}, [InvalidDuration, ..])
	validate_duration = |duration| match duration {
		Coordinate(delta) => if PosixDelta.to_microseconds(delta) > 0 {
			Ok({})
		} else {
			Err(InvalidDuration)
		}
		Calendar(spec) => {
			parts = CalendarDelta.to_components(spec.delta)
			tail = PosixDelta.to_microseconds(spec.tail)
			if parts.years < 0 or parts.months < 0 or parts.days < 0 or tail < 0 or (parts.years == 0 and parts.months == 0 and parts.days == 0 and tail == 0) {
				Err(InvalidDuration)
			} else {
				Ok({})
			}
		}
	}

	## Components must be nonnegative and at least one must be positive.
	## Calendar work is bounded; zone interpretation resumes through collect.
	## Existing start interpretation and its immutable rules are preserved.
	cursor : id, TimedRecurrence.Occurrence, Duration -> Try(Cursor(id), [InvalidDuration, OutOfRange, OutsideValidity, InvalidDestination(GregorianDate.Fields), ..])
	cursor = |id, start, duration| match duration {
		Coordinate(delta) => {
			validate_duration(duration)?
			end = match PosixBoundary.shift(TimedRecurrence.Occurrence.boundary(start), delta) {
				Ok(value) => value
				Err(OutOfRange) => return Err(OutOfRange)
			}
			value = finish(id, start, duration, end, None)?
			Ok(Ready(value))
		}
		Calendar(spec) => {
			parts = CalendarDelta.to_components(spec.delta)
			validate_duration(duration)?
			source = TimedRecurrence.Occurrence.source(start)
			if parts.years == 0 and parts.months == 0 and parts.days == 0 {
				# Zero calendar movement is identity on the already selected
				# start, including a fold occurrence or before-gap adjustment.
				choice = { boundary: TimedRecurrence.Occurrence.boundary(start), adjustment: TimedRecurrence.Occurrence.adjustment(start) }
				end = match PosixBoundary.shift(choice.boundary, spec.tail) {
					Ok(value) => value
					Err(OutOfRange) => return Err(OutOfRange)
				}
				value = finish(id, start, duration, end, Some({ source, choice }))?
				return Ok(Ready(value))
			}
			# TimedRecurrence constructs Gregorian sources. Conversion through
			# the common day coordinate preserves that established invariant.
			date = match GregorianDate.from_civil_day(CalendarDate.to_civil_day(LocalDateTime.date(source))) {
				Ok(value) => value
				Err(OutOfRange) => return Err(OutOfRange)
			}
			shifted = CalendarArithmetic.shift_day(date, spec.delta, spec.invalid_date)?
			end_source = LocalDateTime.new(CalendarDate.from_gregorian(shifted), LocalDateTime.clock(source))
			pending = match ZoneRules.classification_cursor(TimedRecurrence.Occurrence.rules(start), end_source) {
				Ok(value) => value
				Err(OutOfRange) => return Err(OutOfRange)
				Err(OutsideValidity) => return Err(OutsideValidity)
			}
			Ok(Pending({ id, start, spec, end_source, pending }))
		}
	}
	Cursor(id) :: [Ready(TimedOccurrence(id)), Pending({ id : id, start : TimedRecurrence.Occurrence, spec : CalendarDuration, end_source : LocalDateTime, pending : ZoneRules.ClassificationCursor })].{
		collect : Cursor(id), ZoneRules.ClassificationLimits -> Try(Batch(id), [InvalidDuration, OutOfRange, Gap, Ambiguous, AmbiguousGap, OffsetConflict, ..])
		collect = |state, limits| match state {
			Ready(value) => Ok({ segments: 0, buffered: 0, status: Complete(value) })
			Pending(value) => {
				batch = ZoneRules.ClassificationCursor.collect(value.pending, limits)?
				status = match batch.status {
					Limited(progress) => Limited({ cursor: Pending({ ..value, pending: progress.cursor }), reason: progress.reason })
					Complete(classification) => {
						choice = ZoneRules.Classification.choose(classification, { occurrence: value.spec.occurrence, gap: value.spec.gap })?
						end = PosixBoundary.shift(choice.boundary, value.spec.tail)?
						occurrence = finish(value.id, value.start, Calendar(value.spec), end, Some({ source: value.end_source, choice }))?
						Complete(occurrence)
					}
				}
				Ok({ segments: batch.segments, buffered: batch.buffered, status })
			}
		}
		to_inspect : Cursor(id) -> Str
		to_inspect = |state| match state {
			Ready(_) => "TimedOccurrence.Cursor(ready)"
			Pending(_) => "TimedOccurrence.Cursor(calendar end pending)"
		}
	}
	id : TimedOccurrence(id) -> id
	id = |value| value.id
	start : TimedOccurrence(id) -> TimedRecurrence.Occurrence
	start = |value| value.start
	duration : TimedOccurrence(id) -> Duration
	duration = |value| value.duration
	span : TimedOccurrence(id) -> PosixSpan
	span = |value| value.span

	## The interpreted calendar anchor before adding the coordinate tail.
	calendar_anchor : TimedOccurrence(id) -> [None, Some({ source : LocalDateTime, choice : ZoneRules.BoundaryChoice })]
	calendar_anchor = |value| value.calendar_anchor
	to_inspect : TimedOccurrence(id) -> Str
	to_inspect = |value| "TimedOccurrence(${Str.inspect(value.span)})"
}

finish : id, TimedRecurrence.Occurrence, TimedOccurrence.Duration, PosixBoundary, [None, Some({ source : LocalDateTime, choice : ZoneRules.BoundaryChoice })] -> Try(TimedOccurrence(id), [InvalidDuration, ..])
finish = |id, start, duration, end, calendar_anchor| {
	span = match PosixSpan.new(TimedRecurrence.Occurrence.boundary(start), end) {
		Ok(value) => value
		Err(_) => return Err(InvalidDuration)
	}
	Ok({ id, start, duration, span, calendar_anchor })
}

# Epoch midnight with a one-hour forward jump at noon: the next local midnight
# is 23 POSIX hours later. A fixed 24-hour width has a different endpoint.
test_start = |rules, policy| test_start_at(rules, policy, GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?)

test_start_at = |rules, policy, date| {
	clock = ClockTime.from_microseconds_since_midnight(0)?
	source = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(CalendarArithmetic.shift_day(date, CalendarDelta.days(1), Reject)?), clock)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	cursor = TimedRecurrence.cursor(rule, { start: source, end }, { rules, occurrence: policy, gap: RejectGap })?
	batch = TimedRecurrence.Cursor.next(cursor, { max_steps: 10, max_buffered: 1, max_zone_segments: 10, max_zone_candidates: 2 })?
	match batch.status {
		Item(item) => Ok(item.occurrence)
		_ => crash "fixture start"
	}
}

test_rules = |offset, at| {
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-172800000000), PosixBoundary.from_microseconds(259200000000))?
	ZoneRules.new_bounded(
		"Synthetic/Duration",
		"v1",
		validity,
		FixedOffset.from_seconds(0),
		[{ at: PosixBoundary.from_microseconds(at), offset: FixedOffset.from_seconds(offset) }],
		{
			minimum: if offset < 0 {
				offset
			} else {
				0
			},
			maximum: if offset > 0 {
				offset
			} else {
				0
			},
		},
	)
}

expect {
	start = test_start(test_rules(3600, 43200000000)?, RequireUnique)?
	fixed = TimedOccurrence.cursor("fixed", start, Coordinate(PosixDelta.from_microseconds(86400000000)))?
	fixed_batch = TimedOccurrence.Cursor.collect(fixed, { max_segments: 0, max_candidates: 0 })?
	fixed_value = match fixed_batch.status {
		Complete(value) => value
		Limited(_) => crash "coordinate duration needs no zone work"
	}
	calendar = TimedOccurrence.cursor("calendar", start, Calendar({ delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }))?
	paused = TimedOccurrence.Cursor.collect(calendar, { max_segments: 1, max_candidates: 1 })?
	pending = match paused.status {
		Limited(progress) => progress.cursor
		Complete(_) => crash "calendar end needs both segments"
	}
	resumed = TimedOccurrence.Cursor.collect(pending, { max_segments: 1, max_candidates: 1 })?
	calendar_value = match resumed.status {
		Complete(value) => value
		Limited(_) => crash "calendar end did not resume"
	}
	fixed_batch.segments == 0 and paused.segments == 1 and resumed.segments == 1 and TimedOccurrence.id(calendar_value) == "calendar" and PosixSpan.coordinate_width(TimedOccurrence.span(calendar_value)) == Ok(PosixDelta.from_microseconds(82800000000)) and PosixSpan.coordinate_width(TimedOccurrence.span(fixed_value)) == Ok(PosixDelta.from_microseconds(86400000000))
}

expect {
	# At the backward jump, midnight has two occurrences. A zero calendar
	# movement plus a tail preserves the selected start despite RequireUnique
	# in the unused end policy, and performs no classification.
	start = test_start(test_rules(-3600, 3600000000)?, Last)?
	cursor = TimedOccurrence.cursor(7.U64, start, Calendar({ delta: CalendarDelta.days(0), invalid_date: Reject, tail: PosixDelta.from_microseconds(3600000000), occurrence: RequireUnique, gap: RejectGap }))?
	result = TimedOccurrence.Cursor.collect(cursor, { max_segments: 0, max_candidates: 0 })?
	match result.status {
		Complete(value) => result.segments == 0 and PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(3600000000))
		Limited(_) => Bool.False
	}
}

expect {
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(6000000000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	start = test_start_at(rules, RequireUnique, GregorianDate.from_fields({ year: 1970, month: 1, day: 31 })?)?
	spec = { delta: CalendarDelta.months(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }
	rejected = match TimedOccurrence.cursor("loan", start, Calendar(spec)) {
		Err(InvalidDestination(fields)) => fields == { year: 1970, month: 2, day: 31 }
		_ => Bool.False
	}
	clamped = TimedOccurrence.cursor("loan", start, Calendar({ ..spec, invalid_date: Clamp }))?
	result = TimedOccurrence.Cursor.collect(clamped, { max_segments: 1, max_candidates: 1 })?
	rejected and match result.status {
		Complete(value) => PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(2419200000000))
		Limited(_) => Bool.False
	}
}

expect {
	start = test_start(test_rules(0, 43200000000)?, RequireUnique)?
	zero = match TimedOccurrence.cursor({}, start, Coordinate(PosixDelta.from_microseconds(0))) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
	negative = match TimedOccurrence.cursor({}, start, Calendar({ delta: CalendarDelta.days(-1), invalid_date: Reject, tail: PosixDelta.from_microseconds(172800000000), occurrence: RequireUnique, gap: RejectGap })) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
	zero and negative
}

expect {
	start = test_start(test_rules(-3600, 3600000000)?, Last)?
	overflow = match TimedOccurrence.cursor(1.U64, start, Coordinate(PosixDelta.from_microseconds(I64.highest))) {
		Err(OutOfRange) => Bool.True
		_ => Bool.False
	}
	calendar_overflow = match TimedOccurrence.cursor(1.U64, start, Calendar({ delta: CalendarDelta.years(I64.highest), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })) {
		Err(OutOfRange) => Bool.True
		_ => Bool.False
	}
	overflow and calendar_overflow
}

expect {
	start = test_start(test_rules(0, 43200000000)?, RequireUnique)?
	missing_end = match TimedOccurrence.cursor(1.U64, start, Calendar({ delta: CalendarDelta.days(3), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })) {
		Err(OutsideValidity) => Bool.True
		_ => Bool.False
	}
	# A coordinate duration needs rules only for the already resolved start.
	fixed = TimedOccurrence.cursor(1.U64, start, Coordinate(PosixDelta.from_microseconds(259200000000)))?
	result = TimedOccurrence.Cursor.collect(fixed, { max_segments: 0, max_candidates: 0 })?
	missing_end and match result.status {
		Complete(_) => result.segments == 0
		Limited(_) => Bool.False
	}
}

expect {
	start = test_start(test_rules(-3600, 90000000000)?, RequireUnique)?
	spec = { delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }
	strict = TimedOccurrence.cursor("fold", start, Calendar(spec))?
	ambiguous = match TimedOccurrence.Cursor.collect(strict, { max_segments: 2, max_candidates: 2 }) {
		Err(Ambiguous) => Bool.True
		_ => Bool.False
	}
	last = TimedOccurrence.cursor("fold", start, Calendar({ ..spec, occurrence: Last }))?
	paused = TimedOccurrence.Cursor.collect(last, { max_segments: 2, max_candidates: 1 })?
	var valid = ambiguous
	pending = match paused.status {
		Limited(progress) => {
			valid = valid and progress.reason == BufferLimit
			progress.cursor
		}
		Complete(_) => crash "fold candidates must obey capacity"
	}
	resumed = TimedOccurrence.Cursor.collect(pending, { max_segments: 1, max_candidates: 2 })?
	valid and resumed.segments == 1 and match resumed.status {
		Complete(value) => TimedOccurrence.id(value) == "fold" and PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(90000000000))
		Limited(_) => Bool.False
	}
}

expect {
	start = test_start(test_rules(3600, 86400000000)?, RequireUnique)?
	spec = { delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }
	strict = TimedOccurrence.cursor("gap", start, Calendar(spec))?
	rejected = match TimedOccurrence.Cursor.collect(strict, { max_segments: 2, max_candidates: 1 }) {
		Err(Gap) => Bool.True
		_ => Bool.False
	}
	adjusted = TimedOccurrence.cursor("gap", start, Calendar({ ..spec, gap: UseOffsetBeforeGap }))?
	result = TimedOccurrence.Cursor.collect(adjusted, { max_segments: 2, max_candidates: 1 })?
	rejected and match result.status {
		Complete(value) => {
			evidence = match TimedOccurrence.calendar_anchor(value) {
				Some(anchor) => match anchor.choice.adjustment {
					BeforeGap(_) => Bool.True
					Exact => Bool.False
				}
				None => Bool.False
			}
			evidence and PosixSpan.coordinate_width(TimedOccurrence.span(value)) == Ok(PosixDelta.from_microseconds(86400000000))
		}
		Limited(_) => Bool.False
	}
}
