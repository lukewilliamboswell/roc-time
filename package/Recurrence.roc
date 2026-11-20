import SubdailyPattern as SubdailyPatternType
import ClockPattern as ClockPatternType
import CalendarPattern as CalendarPatternType
import AllDayOccurrence as AllDayOccurrenceType
import AllDayRecurrence
import TimedRecurrence
import DateRecurrence

## Construct and evaluate calendar and clock recurrence rules.
Recurrence :: [].{

	## DateCursor for bounded evaluation or retained state.
	DateCursor : DateRecurrence.Cursor

	## TimedCursor for bounded evaluation or retained state.
	TimedCursor : TimedRecurrence.Cursor

	## TimedStart for bounded evaluation or retained state.
	TimedStart : TimedRecurrence.Occurrence

	## AllDayOccurrenceCursor for bounded evaluation or retained state.
	AllDayOccurrenceCursor(id) : AllDayOccurrenceType.Cursor(id)

	## CalendarFilter for bounded evaluation or retained state.
	CalendarFilter : CalendarPatternType.Filter

	## SubdailyPattern operations and types.
	SubdailyPattern : SubdailyPatternType

	## ClockPattern operations and types.
	ClockPattern : ClockPatternType

	## CalendarPattern operations and types.
	CalendarPattern : CalendarPatternType

	## AllDayOccurrence operations and types.
	AllDayOccurrence(id) : AllDayOccurrenceType(id)

	## AllDayRecurrence operations and types.
	AllDay(id) : AllDayRecurrence(id)

	## TimedRecurrence operations and types.
	Timed : TimedRecurrence

	## DateRecurrence operations and types.
	Date : DateRecurrence

}
