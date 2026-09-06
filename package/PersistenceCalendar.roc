import Calendar
import CalendarDate
import CalendarValue
import QualifiedCalendarValue
import LocalDateTime
import ClockTime

## Internal version-1 native calendar payload grammar. This is not an EDTF or
## ISO adapter. Calendar and supplied resolution remain independent metadata.
## At most 1024 input bytes, ten base fields and eight qualification entries.
## Missing fields are Incomplete; malformed tokens and unsupported names differ.
## Conversion only invokes validated native constructors, never bound lowering.
PersistenceCalendar :: [].{
	Error : [Malformed, Incomplete, TooLarge, OutOfRange, InvalidInteger, UnsupportedCalendar(Str), UnsupportedResolution(Str), UnsupportedScope(Str), UnsupportedQualifier(Str), InvalidMonth, InvalidDay, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, InvalidFraction, UnsupportedPrecision, TooManyQualifications, DuplicateScope(QualifiedCalendarValue.Scope), UnsuppliedComponent(QualifiedCalendarValue.Scope)]
	parse_value : Str -> Try(CalendarValue, Error)
	parse_value = |text| {
		if text.count_utf8_bytes() > 1024 {
			return Err(TooLarge)
		}
		fields = text.split_on(";")
		if fields.len() < 2 {
			return Err(Incomplete)
		}
		calendar = match Calendar.from_name(at(fields, 0)) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		resolution = at(fields, 1)
		count = match resolution {
			"year" => 3.U64
			"month" => 4
			"day" => 5
			"hour" => 6
			"minute" => 7
			"second" => 8
			"fraction" => 10
			"" => return Err(Incomplete)
			_ => return Err(UnsupportedResolution(resolution))
		}
		if fields.len() > count {
			return Err(Malformed)
		}
		if fields.len() < count {
			return Err(Incomplete)
		}
		year = number(at(fields, 2), True)?
		if count == 3 {
			return match CalendarValue.year(calendar, year) {
				Ok(value) => Ok(value)
				Err(error) => Err(error)
			}
		}
		month = byte(at(fields, 3))?
		if count == 4 {
			return match CalendarValue.month(calendar, year, month) {
				Ok(value) => Ok(value)
				Err(error) => Err(error)
			}
		}
		day = byte(at(fields, 4))?
		date = match CalendarDate.from_fields(calendar, { year, month, day }) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		if count == 5 {
			return Ok(CalendarValue.day(date))
		}
		hour = byte(at(fields, 5))?
		if count == 6 {
			return match CalendarValue.hour(date, hour) {
				Ok(value) => Ok(value)
				Err(error) => Err(error)
			}
		}
		minute = byte(at(fields, 6))?
		if count == 7 {
			return match CalendarValue.minute(date, hour, minute) {
				Ok(value) => Ok(value)
				Err(error) => Err(error)
			}
		}
		second = byte(at(fields, 7))?
		if count == 8 {
			return match CalendarValue.second(date, hour, minute, second) {
				Ok(value) => Ok(value)
				Err(error) => Err(error)
			}
		}
		digits = byte(at(fields, 8))?
		fraction = match I64.to_u32_try(number(at(fields, 9), False)?) {
			Ok(value) => value
			Err(_) => return Err(OutOfRange)
		}
		match CalendarValue.fractional_second(date, { hour, minute, second }, { digits, value: fraction }) {
			Ok(value) => Ok(value)
			Err(error) => Err(error)
		}
	}

	to_value_text : CalendarValue -> Str
	to_value_text = |value| {
		local = CalendarValue.start_label(value)
		date = LocalDateTime.date(local)
		fields = CalendarDate.to_fields(date)
		clock = ClockTime.to_fields(LocalDateTime.clock(local))
		(resolution, count) = match CalendarValue.resolution(value) {
			Year => ("year", 3.U8)
			Month => ("month", 4)
			Day => ("day", 5)
			Hour => ("hour", 6)
			Minute => ("minute", 7)
			Second => ("second", 8)
			Fraction(_) => ("fraction", 10)
		}
		var pieces = [Calendar.to_name(CalendarDate.calendar(date)), resolution, fields.year.to_str()]
		if count >= 4 {
			pieces = pieces.append(fields.month.to_str())
		}
		if count >= 5 {
			pieces = pieces.append(fields.day.to_str())
		}
		if count >= 6 {
			pieces = pieces.append(clock.hour.to_str())
		}
		if count >= 7 {
			pieces = pieces.append(clock.minute.to_str())
		}
		if count >= 8 {
			pieces = pieces.append(clock.second.to_str())
		}
		match CalendarValue.resolution(value) {
			Fraction(digits) => {
				# Native constructor proves exact divisibility at retained width.
				var divisor = 1.U32
				var remaining = 6 - digits
				while remaining > 0 {
					divisor = divisor * 10
					remaining = remaining - 1
				}
				pieces = pieces.append(digits.to_str()).append(U32.div_trunc_by(clock.microsecond, divisor).to_str())
			}
			_ => {}
		}
		Str.join_with(pieces, ";")
	}

	parse_qualified : Str -> Try(QualifiedCalendarValue, Error)
	parse_qualified = |text| {
		if text.count_utf8_bytes() > 1024 {
			return Err(TooLarge)
		}
		(base, qualifiers) = match text.split_on("|") {
			[a, b] => (a, b)
			[_] => return Err(Incomplete)
			_ => return Err(Malformed)
		}
		var count = if qualifiers.is_empty() {
			0.U8
		} else {
			1
		}
		for b in qualifiers.to_utf8() {
			if b == 59 {
				count = count + 1
				if count > 8 {
					return Err(TooManyQualifications)
				}
			}
		}
		value = parse_value(base)?
		var qualifications = []
		if !qualifiers.is_empty() {
			for entry in qualifiers.split_on(";") {
				(scope_text, qualifier_text) = match entry.split_on("=") {
					[a, b] => (a, b)
					[_] => return Err(Incomplete)
					_ => return Err(Malformed)
				}
				scope = match scope_text {
					"whole" => Whole
					"year" => Year
					"month" => Month
					"day" => Day
					"hour" => Hour
					"minute" => Minute
					"second" => Second
					"fraction" => Fraction
					"" => return Err(Incomplete)
					_ => return Err(UnsupportedScope(scope_text))
				}
				qualifier = match qualifier_text {
					"uncertain" => Uncertain
					"approximate" => Approximate
					"uncertain-approximate" => UncertainApproximate
					"" => return Err(Incomplete)
					_ => return Err(UnsupportedQualifier(qualifier_text))
				}
				qualifications = qualifications.append({ scope, qualifier })
			}
		}
		match QualifiedCalendarValue.new(value, qualifications) {
			Ok(result) => Ok(result)
			Err(error) => Err(error)
		}
	}

	to_qualified_text : QualifiedCalendarValue -> Str
	to_qualified_text = |qualified| {
		base = to_value_text(QualifiedCalendarValue.described_value(qualified))
		var entries = []
		for q in QualifiedCalendarValue.qualifications(qualified) {
			scope = match q.scope {
				Whole => "whole"
				Year => "year"
				Month => "month"
				Day => "day"
				Hour => "hour"
				Minute => "minute"
				Second => "second"
				Fraction => "fraction"
			}
			qualifier = match q.qualifier {
				Uncertain => "uncertain"
				Approximate => "approximate"
				UncertainApproximate => "uncertain-approximate"
			}
			entries = entries.append("${scope}=${qualifier}")
		}
		"${base}|${Str.join_with(entries, ";")}"
	}
}

number : Str, Bool -> Try(I64, PersistenceCalendar.Error)
number = |text, signed| {
	if text.is_empty() {
		return Err(Incomplete)
	}
	bytes = text.to_utf8()
	negative = bytes.first() == Ok(45)
	if negative and !signed {
		return Err(InvalidInteger)
	}
	start = if negative {
		1.U64
	} else {
		0
	}
	if bytes.len() == start {
		return Err(Incomplete)
	}
	if at(bytes, start) == 48 and (negative or bytes.len() > start + 1) {
		return Err(InvalidInteger)
	}
	for b in bytes.drop_first(start) {
		if b < 48 or b > 57 {
			return Err(InvalidInteger)
		}
	}
	match I64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

byte = |text| match I64.to_u8_try(number(text, False)?) {
	Ok(value) => Ok(value)
	Err(_) => Err(OutOfRange)
}

at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "Native calendar payload length validated before indexed access"
}

expect {
	# Gregorian century rule differs independently from Julian's every-fourth-year rule.
	PersistenceCalendar.parse_value("gregorian;day;1900;2;29") == Err(InvalidDay) and
		PersistenceCalendar.to_value_text(PersistenceCalendar.parse_value("julian;day;1900;2;29")?) == "julian;day;1900;2;29"
}
expect {
	a = PersistenceCalendar.parse_value("gregorian;fraction;2004;6;11;12;30;0;2;12")?
	b = PersistenceCalendar.parse_value("gregorian;fraction;2004;6;11;12;30;0;3;120")?
	a != b and CalendarValue.start_label(a) == CalendarValue.start_label(b) and
		CalendarValue.resolution(a) == Fraction(2) and CalendarValue.resolution(b) == Fraction(3)
}
expect {
	last = PersistenceCalendar.parse_value("julian;day;2147483647;12;31")?
	CalendarValue.local_bounds(last) == Err(OutOfRange) and
		PersistenceCalendar.to_value_text(last) == "julian;day;2147483647;12;31" and
			PersistenceCalendar.to_value_text(PersistenceCalendar.parse_value("gregorian;year;-2147483648")?) == "gregorian;year;-2147483648"
}
expect {
	qualified = PersistenceCalendar.parse_qualified("julian;month;1900;2|month=approximate;whole=uncertain")?
	empty = PersistenceCalendar.parse_qualified("julian;month;1900;2|")?
	PersistenceCalendar.to_qualified_text(qualified) == "julian;month;1900;2|whole=uncertain;month=approximate" and
		QualifiedCalendarValue.qualifications(empty).is_empty() and
			PersistenceCalendar.parse_qualified("gregorian;year;2000|whole=uncertain;whole=approximate") == Err(DuplicateScope(Whole)) and
				PersistenceCalendar.parse_qualified("gregorian;year;2000|month=approximate") == Err(UnsuppliedComponent(Month))
}
expect {
	PersistenceCalendar.parse_value("hebrew;year;2000") == Err(UnsupportedCalendar("hebrew")) and
		PersistenceCalendar.parse_value("gregorian;week;2000") == Err(UnsupportedResolution("week")) and
			PersistenceCalendar.parse_value("gregorian;day;2000;1") == Err(Incomplete) and
				PersistenceCalendar.parse_value("gregorian;year;2000;1") == Err(Malformed) and
					PersistenceCalendar.parse_value("gregorian;year;0200") == Err(InvalidInteger) and
						PersistenceCalendar.parse_value("gregorian;year;-0") == Err(InvalidInteger) and
							PersistenceCalendar.parse_value("gregorian;year;2147483648") == Err(OutOfRange) and
								PersistenceCalendar.parse_value("gregorian;fraction;2000;1;1;0;0;0;7;0") == Err(UnsupportedPrecision) and
									PersistenceCalendar.parse_qualified("gregorian;year;2000|season=uncertain") == Err(UnsupportedScope("season")) and
										PersistenceCalendar.parse_qualified("gregorian;year;2000|whole=maybe") == Err(UnsupportedQualifier("maybe")) and
											PersistenceCalendar.parse_qualified("gregorian;year;2000") == Err(Incomplete) and
												PersistenceCalendar.parse_qualified("gregorian;year;2000||") == Err(Malformed) and
													PersistenceCalendar.parse_qualified("gregorian;year;2000|${Str.join_with(List.repeat("whole=uncertain", 9), ";")}") == Err(TooManyQualifications) and
														PersistenceCalendar.parse_value("x".repeat(1025)) == Err(TooLarge)
}
