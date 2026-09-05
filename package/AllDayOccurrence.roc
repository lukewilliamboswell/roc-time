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
