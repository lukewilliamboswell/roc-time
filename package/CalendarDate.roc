import Calendar
import CivilDay
import GregorianDate
import JulianDate

## A validated day description retaining its calendar. Resolution is one civil day.
CalendarDate :: [Gregorian(GregorianDate), Julian(JulianDate)].{
	Fields : { year : I64, month : U8, day : U8 }

	## Preserve an already validated date and its calendar without revalidation.
	from_gregorian : GregorianDate -> CalendarDate
	from_gregorian = |date| Gregorian(date)
	from_julian : JulianDate -> CalendarDate
	from_julian = |date| Julian(date)

	from_fields : Calendar, Fields -> Try(CalendarDate, [OutOfRange, InvalidMonth, InvalidDay, ..])
	from_fields = |calendar, fields| match calendar {
		Gregorian => match GregorianDate.from_fields(fields) {
			Ok(date) => Ok(Gregorian(date))
			Err(error) => Err(error)
		}
		Julian => match JulianDate.from_fields(fields) {
			Ok(date) => Ok(Julian(date))
			Err(error) => Err(error)
		}
	}

	from_civil_day : Calendar, CivilDay -> Try(CalendarDate, [OutOfRange, ..])
	from_civil_day = |calendar, coordinate| match calendar {
		Gregorian => match GregorianDate.from_civil_day(coordinate) {
			Ok(date) => Ok(Gregorian(date))
			Err(error) => Err(error)
		}
		Julian => match JulianDate.from_civil_day(coordinate) {
			Ok(date) => Ok(Julian(date))
			Err(error) => Err(error)
		}
	}

	to_civil_day : CalendarDate -> CivilDay
	to_civil_day = |date| match date {
		Gregorian(value) => GregorianDate.to_civil_day(value)
		Julian(value) => JulianDate.to_civil_day(value)
	}

	calendar : CalendarDate -> Calendar
	calendar = |date| match date {
		Gregorian(_) => Gregorian
		Julian(_) => Julian
	}

	to_fields : CalendarDate -> Fields
	to_fields = |date| match date {
		Gregorian(value) => GregorianDate.to_fields(value)
		Julian(value) => JulianDate.to_fields(value)
	}

	in_calendar : CalendarDate, Calendar -> Try(CalendarDate, [OutOfRange, ..])
	in_calendar = |date, target| from_civil_day(target, to_civil_day(date))

	## Equal day extent on the shared civil axis, independent of description.
	same_day : CalendarDate, CalendarDate -> Bool
	same_day = |a, b| to_civil_day(a) == to_civil_day(b)

	## Description equality retains calendar identity; use same_day for extents.
	is_eq : CalendarDate, CalendarDate -> Bool
	is_eq = |a, b| match (a, b) {
		(Gregorian(left), Gregorian(right)) => left == right
		(Julian(left), Julian(right)) => left == right
		_ => Bool.False
	}

	to_hash : CalendarDate, Hasher -> Hasher
	to_hash = |date, hasher| match date {
		Gregorian(value) => value.to_hash((0.U8).to_hash(hasher))
		Julian(value) => value.to_hash((1.U8).to_hash(hasher))
	}

	to_inspect : CalendarDate -> Str
	to_inspect = |date| match date {
		Gregorian(value) => Str.inspect(value)
		Julian(value) => Str.inspect(value)
	}

	expect {
		# Independent equal-day anchor: Hinnant's Julian conversion derivation,
		# https://howardhinnant.github.io/date_algorithms.html (2021-09-01).
		julian = from_fields(Julian, { year: 1582, month: 10, day: 5 })?
		gregorian = from_fields(Gregorian, { year: 1582, month: 10, day: 15 })?
		same_day(julian, gregorian) and julian != gregorian and
			in_calendar(julian, Gregorian) == Ok(gregorian)
	}

	expect Calendar.from_name("hebrew") == Err(UnsupportedCalendar("hebrew"))
	expect {
		outer = from_fields(Julian, { year: 2147483647, month: 12, day: 31 })?
		in_calendar(outer, Gregorian) == Err(OutOfRange)
	}
}
