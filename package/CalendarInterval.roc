import Calendar
import QualifiedCalendarValue
import SemanticFact
import CivilDay
import GregorianDate
import JulianDate

## A description of when something began and ended, before timeline interpretation.
## Known endpoints retain their own calendar, year/month/day resolution and scoped
## qualifications. Unknown means missing knowledge; Open explicitly has no bound.
## Neither is an integer sentinel. Both endpoints may be Unknown or Open.
##
## This is not an exact half-open appointment or the coverage of every date
## between two labels. Equal and overlapping civil domains are allowed. Only
## unqualified endpoints with the entire start domain after the entire end
## domain are rejected. Qualifications supply no tolerance, so their apparent
## order cannot establish a contradiction. No zone or satisfiability solver runs.
## Construction and facts visit at most two bounded qualified descriptions.
CalendarInterval :: { start : Endpoint, end : Endpoint }.{

	## Each side's knowledge, independent of the other side's resolution.
	Endpoint : [Known(QualifiedCalendarValue), Unknown, Open]

	## A date-only profile failure or an intrinsically reversed unqualified domain.
	Error : [Start([UnsupportedResolution]), End([UnsupportedResolution]), ReversedBounds]

	## Retain validated date descriptions without requiring exclusive upper bounds
	## to fit a provider. Julian and Gregorian provider limits remain unchanged.
	new : Endpoint, Endpoint -> Try(CalendarInterval, Error)
	new = |start, end| {
		if !date_endpoint(start) {
			return Err(Start(UnsupportedResolution))
		}
		if !date_endpoint(end) {
			return Err(End(UnsupportedResolution))
		}
		match (start, end) {
			(Known(a), Known(b)) => {
				if QualifiedCalendarValue.qualifications(a).is_empty() and QualifiedCalendarValue.qualifications(b).is_empty() {
					first = Calendar.Value.description(QualifiedCalendarValue.described_value(a))
					last = Calendar.Value.description(QualifiedCalendarValue.described_value(b))
					low = validated_date(first.calendar, first.fields)
					month = if last.resolution == Year {
						12.U8
					} else {
						last.fields.month
					}
					day = if last.resolution == Day {
						last.fields.day
					} else {
						month_length(last.calendar, last.fields.year, month)
					}
					high = validated_date(last.calendar, { year: last.fields.year, month, day })
					if CivilDay.to_day_number(Calendar.Date.to_civil_day(low)) > CivilDay.to_day_number(Calendar.Date.to_civil_day(high)) {
						return Err(ReversedBounds)
					}
				}
			}
			_ => {}
		}
		Ok({ start, end })
	}

	## Return the retained endpoint declarations, never inferred exact boundaries.
	endpoints : CalendarInterval -> { start : Endpoint, end : Endpoint }
	endpoints = |value| { start: value.start, end: value.end }

	## Report this description type's interpretation capability. This is not a
	## resolver: civil endpoint materialization is currently unsupported.
	interpretation_support : CalendarInterval -> [UnsupportedCivilEndpointModel]
	interpretation_support = |_| UnsupportedCivilEndpointModel

	## Description equality includes endpoint knowledge, calendar, resolution and qualifiers.
	is_eq : CalendarInterval, CalendarInterval -> Bool
	is_eq = |a, b| endpoint_equal(a.start, b.start) and endpoint_equal(a.end, b.end)

	## Hash the same declarations used by description equality.
	to_hash : CalendarInterval, Hasher -> Hasher
	to_hash = |value, hasher| endpoint_hash(value.end, endpoint_hash(value.start, hasher))

	## Summary, endpoint knowledge, then each known endpoint's own facts.
	fact_count : CalendarInterval -> U64
	fact_count = |value| 3 + endpoint_facts(value.start) + endpoint_facts(value.end)

	## Constant bounded indexing. A knowledge fact precedes each known endpoint's
	## date and qualification facts, so mixed resolutions remain independently visible.
	fact_at : CalendarInterval, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| {
		if index == 0 {
			return Item(SemanticFact.new(CalendarIntervalDescription))
		}
		if index == 1 {
			return Item(SemanticFact.new(CalendarEndpoint({ role: Start, knowledge: knowledge(value.start) })))
		}
		start_count = endpoint_facts(value.start)
		if index - 2 < start_count {
			return endpoint_fact(value.start, index - 2)
		}
		if index == 2 + start_count {
			return Item(SemanticFact.new(CalendarEndpoint({ role: End, knowledge: knowledge(value.end) })))
		}
		if index > 2 + start_count {
			return endpoint_fact(value.end, index - 3 - start_count)
		}
		End
	}

	## Bounded semantic inspection; canonical text belongs to an explicit adapter.
	to_inspect : CalendarInterval -> Str
	to_inspect = |value| "CalendarInterval(start=${endpoint_inspect(value.start)}, end=${endpoint_inspect(value.end)}, unresolved)"
}

date_endpoint = |endpoint| match endpoint {
	Known(description) => match Calendar.Value.resolution(QualifiedCalendarValue.described_value(description)) {
		Year | Month | Day => True
		_ => False
	}
	_ => True
}

validated_date = |calendar, fields| match Calendar.Date.from_fields(calendar, fields) {
	Ok(date) => date
	Err(_) => crash "Validated year/month/day description and provider month length"
}

month_length = |calendar, year, month| match (
	match calendar {
		Gregorian => GregorianDate.days_in_month(year, month)
		Julian => JulianDate.days_in_month(year, month)
	}
) {
	Ok(length) => length
	Err(_) => crash "Validated calendar description supplies a provider year and month"
}

endpoint_inspect = |endpoint| match endpoint {
	Known(value) => Str.inspect(value)
	Unknown => "Unknown"
	Open => "Open"
}

endpoint_equal = |a, b| match (a, b) {
	(Known(left), Known(right)) => left == right
	(Unknown, Unknown) | (Open, Open) => True
	_ => False
}

endpoint_hash = |endpoint, hasher| match endpoint {
	Known(value) => value.to_hash((0.U8).to_hash(hasher))
	Unknown => (1.U8).to_hash(hasher)
	Open => (2.U8).to_hash(hasher)
}

knowledge = |endpoint| match endpoint {
	Known(_) => Known
	Unknown => Unknown
	Open => Open
}

endpoint_facts = |endpoint| match endpoint {
	Known(value) => QualifiedCalendarValue.fact_count(value)
	_ => 0.U64
}

endpoint_fact = |endpoint, index| match endpoint {
	Known(value) => QualifiedCalendarValue.fact_at(value, index)
	_ => End
}

expect {
	# A terminal provider year is a valid description even when the next year
	# cannot be represented. Construction must not ask for exclusive bounds.
	last = QualifiedCalendarValue.new(Calendar.Value.year(Gregorian, 2147483647)?, [])?
	value = CalendarInterval.new(Known(last), Known(last))?
	CalendarInterval.endpoints(value).start == Known(last) and CalendarInterval.interpretation_support(value) == UnsupportedCivilEndpointModel
}

expect {
	date = Calendar.Date.from_fields(Gregorian, { year: 2004, month: 6, day: 11 })?
	clock = QualifiedCalendarValue.new(Calendar.Value.hour(date, 12)?, [])?
	CalendarInterval.new(Known(clock), Unknown) == Err(Start(UnsupportedResolution)) and
		CalendarInterval.new(Open, Known(clock)) == Err(End(UnsupportedResolution))
}

expect {
	# Equal civil dates are meaningful endpoint descriptions, not EmptySpan.
	date = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(Gregorian, { year: 2004, month: 6, day: 11 })?), [])?
	value = CalendarInterval.new(Known(date), Known(date))?
	summary = Str.inspect(value)
	summary.contains("2004-06-11") and summary.contains("Day") and summary.count_utf8_bytes() <= 600 and
		CalendarInterval.fact_count(value) == 7 and
			CalendarInterval.fact_at(value, 1) == Item(SemanticFact.new(CalendarEndpoint({ role: Start, knowledge: Known }))) and
				CalendarInterval.fact_at(value, 4) == Item(SemanticFact.new(CalendarEndpoint({ role: End, knowledge: Known }))) and
					CalendarInterval.fact_at(value, 7) == End
}

expect {
	# Independent equal-day anchors: julian.jsonl id100 and gregorian.jsonl
	# id112 both identify civil day -141427. Calendar identity is retained even
	# when the endpoints describe the same day.
	julian = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(Julian, { year: 1582, month: 10, day: 5 })?), [])?
	gregorian = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(Gregorian, { year: 1582, month: 10, day: 15 })?), [])?
	next_julian = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(Julian, { year: 1582, month: 10, day: 6 })?), [])?
	CalendarInterval.new(Known(julian), Known(gregorian)).is_ok() and
		CalendarInterval.new(Known(gregorian), Known(julian)).is_ok() and
			CalendarInterval.new(Known(next_julian), Known(gregorian)) == Err(ReversedBounds)
}

expect {
	var $valid = True
	for calendar in [Gregorian, Julian] {
		first = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(calendar, { year: -2147483648, month: 1, day: 1 })?), [])?
		second = QualifiedCalendarValue.new(Calendar.Value.day(Calendar.Date.from_fields(calendar, { year: -2147483648, month: 1, day: 2 })?), [])?
		$valid = $valid and CalendarInterval.new(Known(first), Known(first)).is_ok() and
			CalendarInterval.new(Known(second), Known(first)) == Err(ReversedBounds)
	}
	$valid
}
