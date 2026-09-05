import CalendarPattern
import DateRecurrence
import GregorianDate

## RFC 5545 DATE recurrence value adapter, profile date-values-v1.
## Input fields are already extracted property values, not content lines or an
## ICS document. DTSTART/RDATE/EXDATE/UNTIL use YYYYMMDD, years 0001–9999.
## DAILY/WEEKLY/MONTHLY/YEARLY, date selectors, WKST, COUNT and UNTIL are
## supported. Return the same DateRecurrence used by native constructors.
## Timed values, subdaily frequencies, extensions and implicit YEARLY defaults
## described below are explicit unsupported scopes. No source spelling,
## serialization, full iCalendar, or full RFC conformance claim is made.
RfcDateRule :: [].{
	profile : Str
	profile = "rfc5545-date-values-v1"
	Parts : { start : Str, rule : Str, inclusions : List(Str), exclusions : List(Str) }
	Error : [Malformed(Str), Duplicate(Str), Missing(Str), Unsupported(Str), OutOfRange(Str), Incompatible(Str), InvalidDate(Str), TooLarge, InvalidRule([InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), InvalidCount, InvalidUntil, UnsynchronizedStart, OutOfRange])]

	## At most 65536 input bytes in total and 4096 supplied inclusion/exclusion
	## strings each. RDATE/EXDATE entries may contain comma-separated dates;
	## each expanded list and selector list is limited to 4096 values.
	## Parse O(input bytes + supplied entries), then bounded DateRecurrence construction. Never
	## expand a series here. Names/enumerations are ASCII case-insensitive;
	## whitespace, folded lines, duplicate keys and numeric overflow are errors.
	parse : Parts -> Try(DateRecurrence, Error)
	parse = |parts| {
		if parts.inclusions.len() > 4096 or parts.exclusions.len() > 4096 {
			return Err(TooLarge)
		}
		var remaining = 65536.U64
		for value in [parts.start, parts.rule].concat(parts.inclusions).concat(parts.exclusions) {
			if value.count_utf8_bytes() > remaining {
				return Err(TooLarge)
			}
			remaining = remaining - value.count_utf8_bytes()
		}
		anchor = parse_date(parts.start, "DTSTART")?
		text = ascii_upper(parts.rule)?
		var pattern = CalendarPattern.defaults(Daily)
		var termination = Forever
		var positions = []
		var seen = []
		for entry in text.split_on(";") {
			(key, value) = match entry.split_on("=") {
				[name, content] => if name.is_empty() or content.is_empty() {
					return Err(Malformed("RRULE part"))
				} else {
					(name, content)
				}
				_ => return Err(Malformed("RRULE part"))
			}
			if seen.contains(key) {
				return Err(Duplicate(key))
			}
			seen = seen.append(key)
			match key {
				"FREQ" => {
					frequency = match value {
						"DAILY" => Daily
						"WEEKLY" => Weekly
						"MONTHLY" => Monthly
						"YEARLY" => Yearly
						"SECONDLY" | "MINUTELY" | "HOURLY" => return Err(Unsupported("subdaily DATE recurrence"))
						_ => return Err(Malformed("FREQ"))
					}
					pattern = { ..pattern, frequency }
				}
				"INTERVAL" => {
					pattern = { ..pattern, interval: positive(key, value, 65536, 2147483647)? }
				}
				"COUNT" => {
					termination = Count(positive(key, value, 65536, 2147483647)?.to_u64_wrap())
				}
				"UNTIL" => {
					termination = Until(parse_date(value, "UNTIL")?)
				}
				"WKST" => {
					pattern = { ..pattern, week_start: weekday(value)? }
				}
				"BYMONTH" => {
					pattern = { ..pattern, by_month: numbers(key, value, 2, 12, False)?.map(|n| n.to_u8_wrap()) }
				}
				"BYMONTHDAY" => {
					pattern = { ..pattern, by_month_day: numbers(key, value, 2, 31, True)?.map(|n| n.to_i8_wrap()) }
				}
				"BYYEARDAY" => {
					pattern = { ..pattern, by_year_day: numbers(key, value, 3, 366, True)?.map(|n| n.to_i16_wrap()) }
				}
				"BYWEEKNO" => {
					pattern = { ..pattern, by_week_no: numbers(key, value, 2, 53, True)?.map(|n| n.to_i8_wrap()) }
				}
				"BYSETPOS" => {
					positions = numbers(key, value, 3, 366, True)?.map(|n| n.to_i16_wrap())
				}
				"BYDAY" => {
					var days = []
					for day in value.split_on(",") {
						if days.len() == 4096 {
							return Err(TooLarge)
						}
						bytes = day.to_utf8()
						if bytes.len() < 2 {
							return Err(Malformed("BYDAY"))
						}
						suffix = ascii(bytes.drop_first(bytes.len() - 2))
						prefix = ascii(bytes.take_first(bytes.len() - 2))
						ordinal = if prefix.is_empty() {
							0.I64
						} else {
							signed_number("BYDAY", prefix, 2, 53, True)?
						}
						days = days.append({ ordinal: ordinal.to_i8_wrap(), weekday: weekday(suffix)? })
					}
					pattern = { ..pattern, by_day: days }
				}
				"BYHOUR" | "BYMINUTE" | "BYSECOND" => return Err(Incompatible("clock selector with DATE"))
				_ => return Err(Unsupported(key))
			}
		}
		if !seen.contains("FREQ") {
			return Err(Missing("FREQ"))
		}
		if seen.contains("COUNT") and seen.contains("UNTIL") {
			return Err(Incompatible("COUNT and UNTIL"))
		}
		if !positions.is_empty() and pattern.by_month.is_empty() and pattern.by_month_day.is_empty() and pattern.by_year_day.is_empty() and pattern.by_week_no.is_empty() and pattern.by_day.is_empty() {
			return Err(Incompatible("BYSETPOS requires another BY selector"))
		}
		# RFC 5545's derivation prose/table and RFC 8984's explicit implicit-field
		# rules are not interchangeable. Require explicit fields in the disputed
		# intersection rather than silently adopt dateutil or JSCalendar defaults.
		if pattern.frequency == Yearly and pattern.by_year_day.is_empty() {
			if pattern.by_month.is_empty() and pattern.by_week_no.is_empty() and !pattern.by_month_day.is_empty() {
				return Err(Unsupported("YEARLY BYMONTHDAY requires explicit BYMONTH in this profile"))
			}
			if !pattern.by_week_no.is_empty() and pattern.by_month_day.is_empty() and pattern.by_day.is_empty() {
				return Err(Unsupported("YEARLY BYWEEKNO requires explicit BYDAY in this profile"))
			}
		}
		inclusions = parse_dates(parts.inclusions, "RDATE")?
		exclusions = parse_dates(parts.exclusions, "EXDATE")?
		match DateRecurrence.new(anchor, { pattern, termination, by_set_pos: positions, inclusions, exclusions }) {
			Ok(rule) => Ok(rule)
			Err(error) => Err(InvalidRule(error))
		}
	}
}

parse_date : Str, Str -> Try(GregorianDate, RfcDateRule.Error)
parse_date = |text, part| {
	bytes = text.to_utf8()
	if bytes.len() != 8 {
		# Recognize a basic DATE-TIME shape before reporting a type mismatch;
		# arbitrary malformed text containing T is still malformed input.
		if bytes.len() == 15 or bytes.len() == 16 {
			for byte in bytes {
				if byte > 127 {
					return Err(Malformed(part))
				}
			}
			separator = ascii(bytes.sublist({ start: 8, len: 1 }))
			suffix = ascii(bytes.drop_first(15))
			if (separator == "T" or separator == "t") and (suffix == "" or suffix == "Z" or suffix == "z") {
				_date = parse_date(ascii(bytes.take_first(8)), part)?
				var clock = 0.I64
				for byte in bytes.sublist({ start: 9, len: 6 }) {
					if byte < 48 or byte > 57 {
						return Err(Malformed(part))
					}
					clock = clock * 10 + byte.to_i64() - 48
				}
				if I64.div_trunc_by(clock, 10000) > 23 or I64.mod_by(I64.div_trunc_by(clock, 100), 100) > 59 or I64.mod_by(clock, 100) > 60 {
					return Err(Malformed(part))
				}
				return Err(Incompatible("DATE-TIME with DATE"))
			}
		}
		return Err(Malformed(part))
	}
	var value = 0.I64
	for byte in bytes {
		if byte < 48 or byte > 57 {
			return Err(Malformed(part))
		}
		value = value * 10 + byte.to_i64() - 48
	}
	year = I64.div_trunc_by(value, 10000)
	if year == 0 {
		return Err(OutOfRange(part))
	}
	# Eight decimal digits establish exact narrowing for the two-digit fields.
	month = I64.mod_by(I64.div_trunc_by(value, 100), 100).to_u8_wrap()
	day = I64.mod_by(value, 100).to_u8_wrap()
	match GregorianDate.from_fields({ year, month, day }) {
		Ok(date) => Ok(date)
		Err(_) => Err(InvalidDate(part))
	}
}

parse_dates : List(Str), Str -> Try(List(GregorianDate), RfcDateRule.Error)
parse_dates = |entries, part| {
	var dates = []
	for entry in entries {
		for value in entry.split_on(",") {
			if dates.len() == 4096 {
				return Err(TooLarge)
			}
			dates = dates.append(parse_date(value, part)?)
		}
	}
	Ok(dates)
}

positive : Str, Str, U64, I64 -> Try(I64, RfcDateRule.Error)
positive = |part, text, digits, limit| {
	bytes = text.to_utf8()
	if bytes.is_empty() or bytes.len() > digits {
		return Err(Malformed(part))
	}
	var value = 0.I64
	for byte in bytes {
		if byte < 48 or byte > 57 {
			return Err(Malformed(part))
		}
		digit = byte.to_i64() - 48
		if value > I64.div_trunc_by(limit - digit, 10) {
			return Err(OutOfRange(part))
		}
		value = value * 10 + digit
		if value > limit {
			return Err(OutOfRange(part))
		}
	}
	if value == 0 {
		return Err(OutOfRange(part))
	}
	Ok(value)
}

signed_number : Str, Str, U64, I64, Bool -> Try(I64, RfcDateRule.Error)
signed_number = |part, text, digits, limit, allow_sign| {
	if allow_sign and text.starts_with("-") {
		return Ok(-positive(part, text.drop_prefix("-"), digits, limit)?)
	}
	if allow_sign and text.starts_with("+") {
		return positive(part, text.drop_prefix("+"), digits, limit)
	}
	positive(part, text, digits, limit)
}

numbers : Str, Str, U64, I64, Bool -> Try(List(I64), RfcDateRule.Error)
numbers = |part, text, digits, limit, allow_sign| {
	var result = []
	for value in text.split_on(",") {
		if result.len() == 4096 {
			return Err(TooLarge)
		}
		result = result.append(signed_number(part, value, digits, limit, allow_sign)?)
	}
	Ok(result)
}

weekday : Str -> Try(CalendarPattern.Weekday, RfcDateRule.Error)
weekday = |text| match text {
	"MO" => Ok(Monday)
	"TU" => Ok(Tuesday)
	"WE" => Ok(Wednesday)
	"TH" => Ok(Thursday)
	"FR" => Ok(Friday)
	"SA" => Ok(Saturday)
	"SU" => Ok(Sunday)
	_ => Err(Malformed("weekday"))
}

ascii_upper : Str -> Try(Str, RfcDateRule.Error)
ascii_upper = |text| {
	var bytes = []
	for byte in text.iter_utf8() {
		if byte < 33 or byte > 126 {
			return Err(Malformed("RRULE ASCII token"))
		}
		bytes = bytes.append(
			if byte >= 97 and byte <= 122 {
				byte - 32
			} else {
				byte
			},
		)
	}
	Ok(ascii(bytes))
}

ascii = |bytes| match Str.from_utf8(bytes) {
	Ok(text) => text
	Err(_) => crash "Validated ASCII bytes"
}
