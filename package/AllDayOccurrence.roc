import FixedOffset
import PosixBoundary
import PosixDelta
import PosixSpan
import CalendarDate
import CivilDay
import ClockTime
import Coverage
import LocalDateTime
import ResolvedSelection
import ZoneRules

## An identified civil-day selection, including occurrences with empty coverage.
## Pair an application series ID with the original date for recurrence identity.
## Duration counts civil days, never fixed 24-hour elapsed quantities.
AllDayOccurrence(id) :: { id : id, date : CalendarDate, days : U64, selection : ResolvedSelection }.{

	## Constant calendar work; zone interpretation is deferred to the cursor.
	## Both the source and exclusive end must fit the source calendar and rules.
	cursor : id, CalendarDate, U64, ZoneRules -> Try(Cursor(id), [InvalidDuration, OutOfRange, OutsideValidity, ..])
	cursor = |id, date, days, rules| {
		if days == 0 {
			return Err(InvalidDuration)
		}
		start_number = CivilDay.to_day_number(CalendarDate.to_civil_day(date))
		end_number = match I128.to_i64_try(start_number.to_i128() + days.to_i128()) {
			Ok(value) => value
			Err(OutOfRange) => return Err(OutOfRange)
		}
		end = match CalendarDate.from_civil_day(CalendarDate.calendar(date), CivilDay.from_day_number(end_number)) {
			Ok(value) => value
			Err(OutOfRange) => return Err(OutOfRange)
		}
		midnight = midnight_clock(0)
		pending = match ZoneRules.selection_cursor(rules, LocalDateTime.new(date, midnight), LocalDateTime.new(end, midnight)) {
			Ok(value) => value
			Err(EmptySelection) => crash "positive civil duration is nonempty"
			Err(ReversedSelection) => crash "positive civil duration is ordered"
			Err(OutsideValidity) => return Err(OutsideValidity)
			Err(OutOfRange) => return Err(OutOfRange)
		}
		Ok({ id, date, days, pending })
	}

	Batch(id) : {
		segments : U64,
		buffered : U64,
		status : [Complete(AllDayOccurrence(id)), Limited({ cursor : Cursor(id), reason : [WorkLimit, BufferLimit] })],
	}
	Cursor(id) :: { id : id, date : CalendarDate, days : U64, pending : ZoneRules.SelectionCursor }.{
		collect : Cursor(id), ZoneRules.SelectionLimits -> Try(Batch(id), [OutOfRange, ..])
		collect = |state, limits| {
			batch = ResolvedSelection.collect(state.pending, limits)?
			status = match batch.status {
				Complete(selection) => Complete({ id: state.id, date: state.date, days: state.days, selection })
				Limited(progress) => Limited({ cursor: { ..state, pending: progress.cursor }, reason: progress.reason })
			}
			Ok({ segments: batch.segments, buffered: batch.buffered, status })
		}
		to_inspect : Cursor(id) -> Str
		to_inspect = |state| "AllDayOccurrence.Cursor(${Str.inspect(state.date)}, days=${state.days.to_str()})"
	}
	id : AllDayOccurrence(id) -> id
	id = |occurrence| occurrence.id
	date : AllDayOccurrence(id) -> CalendarDate
	date = |occurrence| occurrence.date
	days : AllDayOccurrence(id) -> U64
	days = |occurrence| occurrence.days
	selection : AllDayOccurrence(id) -> ResolvedSelection
	selection = |occurrence| occurrence.selection
	coverage : AllDayOccurrence(id) -> Coverage
	coverage = |occurrence| ResolvedSelection.coverage(occurrence.selection)
	to_inspect : AllDayOccurrence(id) -> Str
	to_inspect = |occurrence| "AllDayOccurrence(${Str.inspect(occurrence.date)}, days=${occurrence.days.to_str()}, ${Str.inspect(coverage(occurrence))})"
}

midnight_clock = |number| match ClockTime.from_microseconds_since_midnight(number) {
	Ok(value) => value
	Err(_) => crash "midnight invariant"
}

test_alldayoccurrence_point = PosixBoundary.from_microseconds

test_alldayoccurrence_day = |number| CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: number })

# Independent constant-offset segment arithmetic: changing at epoch+2h makes
# the first civil date 23h, 25h, or unchanged. A +24h jump at epoch skips it.
expect {
	var valid = Bool.True
	for (at, offset, hours) in [(7200000000.I64, 3600.I32, 23.I64), (7200000000, -3600, 25), (7200000000, 0, 24), (0, 86400, 0)] {
		validity = PosixSpan.new(test_alldayoccurrence_point(-259200000000), test_alldayoccurrence_point(259200000000))?
		rules = ZoneRules.new_bounded("Synthetic/Day", "v1", validity, FixedOffset.from_seconds(0), [{ at: test_alldayoccurrence_point(at), offset: FixedOffset.from_seconds(offset) }], { minimum: I32.min(0, offset), maximum: I32.max(0, offset) })?
		date = test_alldayoccurrence_day(1)?
		initial = AllDayOccurrence.cursor({ series: "visits", date }, date, 1, rules)?
		first = AllDayOccurrence.Cursor.collect(initial, { max_segments: 1, max_members: 1 })?
		match first.status {
			Complete(_) => {
				valid = Bool.False
			}
			Limited(progress) => {
				last = AllDayOccurrence.Cursor.collect(progress.cursor, { max_segments: 1, max_members: 1 })?
				match last.status {
					Limited(_) => {
						valid = Bool.False
					}
					Complete(value) => {
						valid = valid and AllDayOccurrence.id(value) == { series: "visits", date } and
							AllDayOccurrence.date(value) == date and AllDayOccurrence.days(value) == 1 and
								Coverage.coordinate_width(AllDayOccurrence.coverage(value)) == Ok(PosixDelta.from_microseconds(hours * 3600000000)) and
									ZoneRules.version(ResolvedSelection.rules(AllDayOccurrence.selection(value))) == "v1"
					}
				}
			}
		}
	}
	valid
}

expect {
	validity = PosixSpan.new(test_alldayoccurrence_point(-259200000000), test_alldayoccurrence_point(259200000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	date = test_alldayoccurrence_day(1)?
	zero = match AllDayOccurrence.cursor(0.U64, date, 0, rules) {
		Err(InvalidDuration) => True
		_ => False
	}
	huge = match AllDayOccurrence.cursor(0.U64, date, U64.highest, rules) {
		Err(OutOfRange) => True
		_ => False
	}
	missing = match AllDayOccurrence.cursor(0.U64, date, 4, rules) {
		Err(OutsideValidity) => True
		_ => False
	}
	julian = CalendarDate.in_calendar(date, Julian)?
	initial = AllDayOccurrence.cursor("two-test_alldayoccurrence_day-visit", julian, 2, rules)?
	limited = AllDayOccurrence.Cursor.collect(initial, { max_segments: 0, max_members: 1 })?
	resumed = match limited.status {
		Complete(_) => False
		Limited(progress) => {
			batch = AllDayOccurrence.Cursor.collect(progress.cursor, { max_segments: 1, max_members: 1 })?
			match batch.status {
				Limited(_) => False
				Complete(value) => AllDayOccurrence.date(value) == julian and
					AllDayOccurrence.days(value) == 2 and
						Coverage.coordinate_width(AllDayOccurrence.coverage(value)) == Ok(PosixDelta.from_microseconds(172800000000))
			}
		}
	}
	zero and huge and missing and resumed
}
