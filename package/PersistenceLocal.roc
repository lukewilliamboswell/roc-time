import LocalDateTime
import CalendarDate
import Calendar
import ClockTime
import CalendarValue
import PersistenceCalendar

## Internal exact local-label transport shared by native archives. This is
## calendar;fraction;year;month;day;hour;minute;second;6;microsecond, with native
## Gregorian/Julian year numbering and canonical integers. No zone resolution.
PersistenceLocal := [].{
	Error : [Malformed, InvalidLocal(PersistenceCalendar.Error)]
	to_text : LocalDateTime -> Str
	to_text = |local| {
		date = LocalDateTime.date(local)
		fields = CalendarDate.to_fields(date)
		clock = ClockTime.to_fields(LocalDateTime.clock(local))
		Str.join_with([Calendar.to_name(CalendarDate.calendar(date)), "fraction", fields.year.to_str(), fields.month.to_str(), fields.day.to_str(), clock.hour.to_str(), clock.minute.to_str(), clock.second.to_str(), "6", clock.microsecond.to_str()], ";")
	}
	parse : Str -> Try(LocalDateTime, Error)
	parse = |text| {
		parsed = match PersistenceCalendar.parse_value(text) {
			Ok(value) => value
			Err(error) => return Err(InvalidLocal(error))
		}
		if CalendarValue.resolution(parsed) != Fraction(6) {
			return Err(Malformed)
		}
		Ok(CalendarValue.start_label(parsed))
	}
}

# R01/R05/R14: independently specified exact fields, including astronomical
# year zero and a Julian description. This does not resolve an exclusive bound.
expect {
	source = PersistenceLocal.parse("julian;fraction;0;2;29;23;59;59;6;999999")?
	CalendarDate.to_fields(LocalDateTime.date(source)) == { year: 0, month: 2, day: 29 } and
		CalendarDate.calendar(LocalDateTime.date(source)) == Julian and
			ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(source)) == 86399999999 and
				PersistenceLocal.parse("gregorian;second;1970;1;1;0;0;0") == Err(Malformed)
}
