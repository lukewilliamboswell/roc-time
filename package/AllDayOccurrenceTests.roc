import AllDayOccurrence
import CalendarDate
import Coverage
import FixedOffset
import PosixBoundary
import PosixDelta
import PosixSpan
import ResolvedSelection
import ZoneRules

AllDayOccurrenceTests :: [].{}

point = PosixBoundary.from_microseconds

day = |number| CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: number })

# Independent constant-offset segment arithmetic: changing at epoch+2h makes
# the first civil date 23h, 25h, or unchanged. A +24h jump at epoch skips it.
expect {
	var valid = Bool.True
	for (at, offset, hours) in [(7200000000.I64, 3600.I32, 23.I64), (7200000000, -3600, 25), (7200000000, 0, 24), (0, 86400, 0)] {
		validity = PosixSpan.new(point(-259200000000), point(259200000000))?
		rules = ZoneRules.new_bounded("Synthetic/Day", "v1", validity, FixedOffset.from_seconds(0), [{ at: point(at), offset: FixedOffset.from_seconds(offset) }], { minimum: I32.min(0, offset), maximum: I32.max(0, offset) })?
		date = day(1)?
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
	validity = PosixSpan.new(point(-259200000000), point(259200000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	date = day(1)?
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
	initial = AllDayOccurrence.cursor("two-day-visit", julian, 2, rules)?
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
