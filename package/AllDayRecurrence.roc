import CalendarPattern
import Coverage
import FixedOffset
import PosixBoundary
import PosixSpan
import AllDayOccurrence
import CalendarDate
import DateRecurrence
import GregorianDate
import ZoneRules

## Stream identified all-day occurrences in source-date order. The window
## selects source dates, not timeline overlaps. Duration may extend beyond it.
## IDs pair the supplied series identity with each original Gregorian date.
AllDayRecurrence(id) :: {
	series : id,
	days : U64,
	rules : ZoneRules,
	dates : DateRecurrence.Cursor,
	date_buffered : U64,
	zone_buffered : U64,
	pending : [None, Some(AllDayOccurrence.Cursor({ series : id, date : GregorianDate }))],
}.{
	new : id, DateRecurrence, DateRecurrence.Window, U64, ZoneRules -> Try(AllDayRecurrence(id), [InvalidDuration, EmptyWindow, ReversedWindow, ..])
	new = |series, rule, window, days, rules| {
		if days == 0 {
			return Err(InvalidDuration)
		}
		dates = DateRecurrence.cursor(rule, window)?
		Ok({ series, days, rules, dates, date_buffered: 0, zone_buffered: 0, pending: None })
	}
	Limits : { max_date_steps : U64, max_date_buffered : U64, max_zone_segments : U64, max_zone_members : U64 }
	Limit : [DateWorkLimit, DateBufferLimit, ZoneWorkLimit, ZoneBufferLimit, OutputLimit]
	Batch(id) : {
		occurrences : List(AllDayOccurrence({ series : id, date : GregorianDate })),
		date_steps : U64,
		zone_segments : U64,
		status : [Complete, Limited({ cursor : AllDayRecurrence(id), reason : Limit })],
	}

	## Materialize at most max_occurrences. Work budgets apply to the whole
	## call, not separately to each emitted occurrence. Reaching output capacity
	## returns Limited without looking ahead to prove End. Resume its cursor.
	collect : AllDayRecurrence(id), { work : Limits, max_occurrences : U64 } -> Try(Batch(id), [OutOfRange, OutsideValidity, ..])
	collect = |initial, budget| {
		var $state = initial
		var $occurrences = []
		var $date_steps = 0.U64
		var $zone_segments = 0.U64
		while $occurrences.len() < budget.max_occurrences {
			batch = next($state, { ..budget.work, max_date_steps: budget.work.max_date_steps - $date_steps, max_zone_segments: budget.work.max_zone_segments - $zone_segments })?
			$date_steps = $date_steps + batch.date_steps
			$zone_segments = $zone_segments + batch.zone_segments
			match batch.status {
				End => return Ok({ occurrences: $occurrences, date_steps: $date_steps, zone_segments: $zone_segments, status: Complete })
				Limited(progress) => return Ok({ occurrences: $occurrences, date_steps: $date_steps, zone_segments: $zone_segments, status: Limited(progress) })
				Item(item) => {
					$occurrences = $occurrences.append(item.occurrence)
					$state = item.cursor
				}
			}
		}
		Ok({ occurrences: $occurrences, date_steps: $date_steps, zone_segments: $zone_segments, status: Limited({ cursor: $state, reason: OutputLimit }) })
	}
	Next(id) : {
		date_steps : U64,
		date_buffered : U64,
		zone_segments : U64,
		zone_buffered : U64,
		status : [End, Item({ occurrence : AllDayOccurrence({ series : id, date : GregorianDate }), cursor : AllDayRecurrence(id) }), Limited({ cursor : AllDayRecurrence(id), reason : Limit })],
	}

	## At most one date-cursor advance and one bounded zone-cursor advance.
	## A pending occurrence resumes before any new date is consumed. Empty
	## coverage still emits an occurrence; skipped civil days do not erase IDs.
	next : AllDayRecurrence(id), Limits -> Try(Next(id), [OutOfRange, OutsideValidity, ..])
	next = |initial, limits| {
		var $state = initial
		var $date_steps = 0.U64
		if $state.date_buffered > limits.max_date_buffered {
			return Ok({ date_steps: 0, date_buffered: $state.date_buffered, zone_segments: 0, zone_buffered: $state.zone_buffered, status: Limited({ cursor: $state, reason: DateBufferLimit }) })
		}
		match $state.pending {
			None => {
				batch = DateRecurrence.Cursor.next($state.dates, { max_steps: limits.max_date_steps, max_buffered: limits.max_date_buffered })?
				$date_steps = batch.steps
				$state = { ..$state, date_buffered: batch.buffered }
				match batch.status {
					End => return Ok({ date_steps: $date_steps, date_buffered: batch.buffered, zone_segments: 0, zone_buffered: 0, status: End })
					Limited(progress) => {
						reason = match progress.reason {
							WorkLimit => DateWorkLimit
							BufferLimit => DateBufferLimit
							OutputLimit => crash "next stops after one date"
						}
						return Ok({ date_steps: $date_steps, date_buffered: batch.buffered, zone_segments: 0, zone_buffered: 0, status: Limited({ cursor: { ..$state, dates: progress.cursor }, reason }) })
					}
					Item(item) => {
						date = CalendarDate.from_gregorian(item.date)
						pending = match AllDayOccurrence.cursor({ series: $state.series, date: item.date }, date, $state.days, $state.rules) {
							Ok(value) => value
							Err(InvalidDuration) => crash "validated positive duration"
							Err(OutOfRange) => return Err(OutOfRange)
							Err(OutsideValidity) => return Err(OutsideValidity)
						}
						$state = { ..$state, dates: item.cursor, pending: Some(pending) }
					}
				}
			}
			Some(_) => {}
		}
		pending = match $state.pending {
			Some(value) => value
			None => crash "date supplied pending occurrence"
		}
		zone = AllDayOccurrence.Cursor.collect(pending, { max_segments: limits.max_zone_segments, max_members: limits.max_zone_members })?
		status = match zone.status {
			Complete(occurrence) => Item({ occurrence, cursor: { ..$state, zone_buffered: 0, pending: None } })
			Limited(progress) => Limited({
				cursor: { ..$state, zone_buffered: zone.buffered, pending: Some(progress.cursor) },
				reason: match progress.reason {
					WorkLimit => ZoneWorkLimit
					BufferLimit => ZoneBufferLimit
				},
			})
		}
		Ok({ date_steps: $date_steps, date_buffered: $state.date_buffered, zone_segments: zone.segments, zone_buffered: zone.buffered, status })
	}

	## Every advancement exposes its outcome. End, errors and Limited are
	## terminal items; resume a Limited cursor explicitly with chosen budgets.
	outcomes : AllDayRecurrence(id), Limits -> Iter(Try(Next(id), [OutOfRange, OutsideValidity]))
	outcomes = |initial, limits| Iter.custom(
		Some(initial),
		Unknown,
		|state| match state {
			None => Err(NoMore)
			Some(current) => {
				result = next(current, limits)
				rest = match result {
					Ok(batch) => match batch.status {
						Item(item) => Some(item.cursor)
						_ => None
					}
					Err(_) => None
				}
				Ok((result, rest))
			}
		},
	)
	to_inspect : AllDayRecurrence(id) -> Str
	to_inspect = |state| "AllDayRecurrence(days=${state.days.to_str()}, ${Str.inspect(state.dates)})"
}

test_alldayrecurrence_date = |day| GregorianDate.from_fields({ year: 1970, month: 1, day })

test_alldayrecurrence_point = PosixBoundary.from_microseconds

# The first counted test_alldayrecurrence_date is skipped by the dateline move, but keeps its ID.
# Pause after test_alldayrecurrence_date generation and halfway through interpretation; no pause
# may consume the next test_alldayrecurrence_date or replenish COUNT with a replacement occurrence.
expect {
	start = test_alldayrecurrence_date(1)?
	end = test_alldayrecurrence_date(4)?
	rule = DateRecurrence.new(start, { pattern: CalendarPattern.defaults(Daily), termination: Count(2), by_set_pos: [], inclusions: [], exclusions: [] })?
	validity = PosixSpan.new(test_alldayrecurrence_point(-259200000000), test_alldayrecurrence_point(432000000000))?
	rules = ZoneRules.new_bounded("Synthetic/Skip", "v1", validity, FixedOffset.from_seconds(0), [{ at: test_alldayrecurrence_point(0), offset: FixedOffset.from_seconds(86400) }], { minimum: 0, maximum: 86400 })?
	initial = AllDayRecurrence.new("service", rule, { start, end }, 1, rules)?
	budget = { max_date_steps: 8.U64, max_date_buffered: 1.U64, max_zone_segments: 0.U64, max_zone_members: 1.U64 }
	first = AllDayRecurrence.next(initial, budget)?
	var $valid = Bool.True
	var $cursor = match first.status {
		Limited(progress) => {
			if progress.reason != ZoneWorkLimit {
				$valid = Bool.False
			}
			progress.cursor
		}
		_ => crash "expected zone pause"
	}
	var $ids = []
	var $empty = []
	var $calls = 0.U64
	var $ended = Bool.False
	while $calls < 30 and !$ended {
		batch = AllDayRecurrence.next($cursor, { ..budget, max_date_steps: 1, max_zone_segments: 1 })?
		$valid = $valid and batch.date_steps <= 1 and batch.zone_segments <= 1
		match batch.status {
			End => {
				$ended = Bool.True
			}
			Limited(progress) => {
				$cursor = progress.cursor
			}
			Item(item) => {
				$ids = $ids.append(AllDayOccurrence.id(item.occurrence))
				$empty = $empty.append(Coverage.member_count(AllDayOccurrence.coverage(item.occurrence)) == 0)
				$cursor = item.cursor
			}
		}
		$calls = $calls + 1
	}
	var $uninterrupted_ids = []
	var $complete = Bool.False
	for result in AllDayRecurrence.outcomes(initial, { ..budget, max_zone_segments: 2 }) {
		batch = result?
		match batch.status {
			End => {
				$complete = Bool.True
			}
			Limited(_) => crash "unexpected uninterrupted limit"
			Item(item) => {
				$uninterrupted_ids = $uninterrupted_ids.append(AllDayOccurrence.id(item.occurrence))
			}
		}
	}
	var $collected_ids = []
	var $collection_cursor = initial
	var $collection_complete = Bool.False
	for _ in [0, 1, 2] {
		batch = AllDayRecurrence.collect($collection_cursor, { work: { ..budget, max_zone_segments: 2 }, max_occurrences: 1 })?
		$valid = $valid and batch.date_steps <= budget.max_date_steps and batch.zone_segments <= 2
		for occurrence in batch.occurrences {
			$collected_ids = $collected_ids.append(AllDayOccurrence.id(occurrence))
		}
		match batch.status {
			Complete => {
				$collection_complete = Bool.True
			}
			Limited(progress) => {
				$valid = $valid and progress.reason == OutputLimit
				$collection_cursor = progress.cursor
			}
		}
	}
	$valid and $ended and $complete and $collection_complete and $ids == [{ series: "service", date: start }, { series: "service", date: test_alldayrecurrence_date(2)? }] and $ids == $uninterrupted_ids and $ids == $collected_ids and $empty == [True, False]
}
