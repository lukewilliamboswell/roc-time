import ICalTimedRule
import ICalDateRule
import ICalPeriod
import ICalDuration
import ICalDateTime

## Parse and export supported iCalendar property values.
ICalendar :: [].{

	## Parse extracted timed iCalendar properties and export canonical values.
	TimedRule : ICalTimedRule

	## ICalDateRule operations and types.
	DateRule : ICalDateRule

	## ICalPeriod operations and types.
	Period : ICalPeriod

	## ICalDuration operations and types.
	Duration : ICalDuration

	## ICalDateTime operations and types.
	DateTime : ICalDateTime

}
