import CalendarPattern
import ClockPattern
import SemanticFact

## Internal fixed-family indexed view of validated recurrence selectors.
## Field list reads share storage; no maps, concatenations or candidate products.
## Date selector lists preserve native declarations; clock fields are effective
## normalized values, including defaults, not original source spelling.
RecurrenceFacts := [].{
	frequency : CalendarPattern.Frequency -> SemanticFact.RecurrenceFrequency
	frequency = |frequency| match frequency {
		Daily => Daily
		Weekly => Weekly
		Monthly => Monthly
		Yearly => Yearly
	}
	count : CalendarPattern.Spec, [None, Some(ClockPattern)], List(I16) -> U64
	count = |calendar, clocks, positions| {
		base = calendar.by_month.len() + calendar.by_month_day.len() + calendar.by_year_day.len() + calendar.by_week_no.len() + calendar.by_day.len() + positions.len()
		base + match clocks {
			None => 0
			Some(clock) => {
				fields = ClockPattern.definition(clock)
				fields.hours.len() + fields.minutes.len() + fields.seconds.len() + 1
			}
		}
	}
	at : CalendarPattern.Spec, [None, Some(ClockPattern)], List(I16), U64 -> [End, Item(SemanticFact)]
	at = |calendar, clocks, positions, index| {
		var $remaining = index
		if $remaining < calendar.by_month.len() {
			return item(Month(get(calendar.by_month, $remaining)))
		}
		$remaining = $remaining - calendar.by_month.len()
		if $remaining < calendar.by_month_day.len() {
			return item(MonthDay(get(calendar.by_month_day, $remaining)))
		}
		$remaining = $remaining - calendar.by_month_day.len()
		if $remaining < calendar.by_year_day.len() {
			return item(YearDay(get(calendar.by_year_day, $remaining)))
		}
		$remaining = $remaining - calendar.by_year_day.len()
		if $remaining < calendar.by_week_no.len() {
			return item(WeekNo(get(calendar.by_week_no, $remaining)))
		}
		$remaining = $remaining - calendar.by_week_no.len()
		if $remaining < calendar.by_day.len() {
			return item(Weekday(get(calendar.by_day, $remaining)))
		}
		$remaining = $remaining - calendar.by_day.len()
		if $remaining < positions.len() {
			return item(SetPosition(get(positions, $remaining)))
		}
		$remaining = $remaining - positions.len()
		match clocks {
			None => End
			Some(clock) => {
				fields = ClockPattern.definition(clock)
				if $remaining < fields.hours.len() {
					return item(Hour(get(fields.hours, $remaining)))
				}
				$remaining = $remaining - fields.hours.len()
				if $remaining < fields.minutes.len() {
					return item(Minute(get(fields.minutes, $remaining)))
				}
				$remaining = $remaining - fields.minutes.len()
				if $remaining < fields.seconds.len() {
					return item(Second(get(fields.seconds, $remaining)))
				}
				$remaining = $remaining - fields.seconds.len()
				if $remaining == 0 {
					item(Microsecond(fields.microsecond))
				} else {
					End
				}
			}
		}
	}
}

item = |selector| Item(SemanticFact.new(RecurrenceSelector(selector)))

get = |items, index| match items.get(index) {
	Ok(result) => result
	Err(_) => crash "Selector index checked against its field length"
}
