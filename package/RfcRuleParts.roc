import CalendarPattern
import ClockPattern
import SubdailyPattern

# Shared syntax lowering for the DATE and DATE-TIME adapters. This module is
# internal to the package; execution remains in the native recurrence types.
RfcRuleParts :: [].{
	Error : [Malformed(Str), Duplicate(Str), Missing(Str), Unsupported(Str), OutOfRange(Str), Incompatible(Str), TooLarge]
	Fields : { pattern : CalendarPattern.Spec, clocks : ClockPattern.Spec, subdaily : [None, Some(SubdailyPattern.Frequency)], termination : [Forever, Count(U64), Until(Str)], positions : List(I16) }
	parse : Str, [Date, Timed] -> Try(Fields, Error)
	parse = |text_input, domain| {
		if text_input.count_utf8_bytes() > 65536 {
			return Err(TooLarge)
		}
		text = ascii_upper(text_input)?
		var $pattern = CalendarPattern.defaults(Daily)
		var $termination = Forever
		var $subdaily = None
		var $clocks = { hours: [], minutes: [], seconds: [] }
		var $positions = []
		var $seen = []
		for entry in text.split_on(";") {
			(key, value) = match entry.split_on("=") {
				[name, content] => if name.is_empty() or content.is_empty() {
					return Err(Malformed("RRULE part"))
				} else {
					(name, content)
				}
				_ => return Err(Malformed("RRULE part"))
			}
			if $seen.contains(key) {
				return Err(Duplicate(key))
			}
			$seen = $seen.append(key)
			match key {
				"FREQ" => {
					frequency = match value {
						"DAILY" => Daily
						"WEEKLY" => Weekly
						"MONTHLY" => Monthly
						"YEARLY" => Yearly
						"SECONDLY" | "MINUTELY" | "HOURLY" => {
							if domain == Date {
								return Err(Unsupported("subdaily DATE recurrence"))
							}
							$subdaily = Some(
								match value {
									"SECONDLY" => Secondly
									"MINUTELY" => Minutely
									_ => Hourly
								},
							)
							Daily
						}
						_ => return Err(Malformed("FREQ"))
					}
					$pattern = { ..$pattern, frequency }
				}
				"INTERVAL" => {
					$pattern = { ..$pattern, interval: positive(key, value, 65536, 2147483647)? }
				}
				"COUNT" => {
					$termination = Count(positive(key, value, 65536, 2147483647)?.to_u64_wrap())
				}
				"UNTIL" => {
					$termination = Until(value)
				}
				"WKST" => {
					$pattern = { ..$pattern, week_start: weekday(value)? }
				}
				"BYMONTH" => {
					$pattern = { ..$pattern, by_month: numbers(key, value, 2, 12, False)?.map(|n| n.to_u8_wrap()) }
				}
				"BYMONTHDAY" => {
					$pattern = { ..$pattern, by_month_day: numbers(key, value, 2, 31, True)?.map(|n| n.to_i8_wrap()) }
				}
				"BYYEARDAY" => {
					$pattern = { ..$pattern, by_year_day: numbers(key, value, 3, 366, True)?.map(|n| n.to_i16_wrap()) }
				}
				"BYWEEKNO" => {
					$pattern = { ..$pattern, by_week_no: numbers(key, value, 2, 53, True)?.map(|n| n.to_i8_wrap()) }
				}
				"BYSETPOS" => {
					$positions = numbers(key, value, 3, 366, True)?.map(|n| n.to_i16_wrap())
				}
				"BYDAY" => {
					var $days = []
					for day in value.split_on(",") {
						if $days.len() == 4096 {
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
						$days = $days.append({ ordinal: ordinal.to_i8_wrap(), weekday: weekday(suffix)? })
					}
					$pattern = { ..$pattern, by_day: $days }
				}
				"BYHOUR" | "BYMINUTE" | "BYSECOND" => {
					if domain == Date {
						return Err(Incompatible("clock selector with DATE"))
					}
					limit = match key {
						"BYHOUR" => 23.I64
						"BYMINUTE" => 59
						_ => 60
					}
					values = clock_numbers(key, value, limit)?
					$clocks = match key {
						"BYHOUR" => { ..$clocks, hours: values }
						"BYMINUTE" => { ..$clocks, minutes: values }
						_ => { ..$clocks, seconds: values }
					}
				}
				_ => return Err(Unsupported(key))
			}
		}
		if !$seen.contains("FREQ") {
			return Err(Missing("FREQ"))
		}
		if $seen.contains("COUNT") and $seen.contains("UNTIL") {
			return Err(Incompatible("COUNT and UNTIL"))
		}
		if !$positions.is_empty() and $pattern.by_month.is_empty() and $pattern.by_month_day.is_empty() and $pattern.by_year_day.is_empty() and $pattern.by_week_no.is_empty() and $pattern.by_day.is_empty() and $clocks.hours.is_empty() and $clocks.minutes.is_empty() and $clocks.seconds.is_empty() {
			return Err(Incompatible("BYSETPOS requires another BY selector"))
		}
		# RFC 5545's derivation prose/table and RFC 8984's explicit implicit-field
		# rules are not interchangeable. Require explicit fields in the disputed
		# intersection rather than silently adopt dateutil or JSCalendar defaults.
		if $pattern.frequency == Yearly and $pattern.by_year_day.is_empty() {
			if $pattern.by_month.is_empty() and $pattern.by_week_no.is_empty() and !$pattern.by_month_day.is_empty() {
				return Err(Unsupported("YEARLY BYMONTHDAY requires explicit BYMONTH in this profile"))
			}
			if !$pattern.by_week_no.is_empty() and $pattern.by_month_day.is_empty() and $pattern.by_day.is_empty() {
				return Err(Unsupported("YEARLY BYWEEKNO requires explicit BYDAY in this profile"))
			}
		}
		match $subdaily {
			Some(_) => {
				if !$pattern.by_week_no.is_empty() {
					return Err(Incompatible("BYWEEKNO requires YEARLY"))
				}
				for day in $pattern.by_day {
					if day.ordinal != 0 {
						return Err(Incompatible("ordinal BYDAY requires MONTHLY or YEARLY"))
					}
				}
			}
			None => {}
		}
		Ok({ pattern: $pattern, clocks: $clocks, subdaily: $subdaily, termination: $termination, positions: $positions })
	}
}

positive : Str, Str, U64, I64 -> Try(I64, RfcRuleParts.Error)
positive = |part, text, digits, limit| {
	bytes = text.to_utf8()
	if bytes.is_empty() or bytes.len() > digits {
		return Err(Malformed(part))
	}
	var $value = 0.I64
	for byte in bytes {
		if byte < 48 or byte > 57 {
			return Err(Malformed(part))
		}
		digit = byte.to_i64() - 48
		if $value > I64.div_trunc_by(limit - digit, 10) {
			return Err(OutOfRange(part))
		}
		$value = $value * 10 + digit
		if $value > limit {
			return Err(OutOfRange(part))
		}
	}
	if $value == 0 {
		return Err(OutOfRange(part))
	}
	Ok($value)
}

signed_number : Str, Str, U64, I64, Bool -> Try(I64, RfcRuleParts.Error)
signed_number = |part, text, digits, limit, allow_sign| {
	if allow_sign and text.starts_with("-") {
		return Ok(-positive(part, text.drop_prefix("-"), digits, limit)?)
	}
	if allow_sign and text.starts_with("+") {
		return positive(part, text.drop_prefix("+"), digits, limit)
	}
	positive(part, text, digits, limit)
}

numbers : Str, Str, U64, I64, Bool -> Try(List(I64), RfcRuleParts.Error)
numbers = |part, text, digits, limit, allow_sign| {
	var $result = []
	for value in text.split_on(",") {
		if $result.len() == 4096 {
			return Err(TooLarge)
		}
		$result = $result.append(signed_number(part, value, digits, limit, allow_sign)?)
	}
	Ok($result)
}

weekday : Str -> Try(CalendarPattern.Weekday, RfcRuleParts.Error)
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

ascii_upper : Str -> Try(Str, RfcRuleParts.Error)
ascii_upper = |text| {
	var $bytes = []
	for byte in text.iter_utf8() {
		if byte < 33 or byte > 126 {
			return Err(Malformed("RRULE ASCII token"))
		}
		$bytes = $bytes.append(
			if byte >= 97 and byte <= 122 {
				byte - 32
			} else {
				byte
			},
		)
	}
	Ok(ascii($bytes))
}

ascii = |bytes| match Str.from_utf8(bytes) {
	Ok(text) => text
	Err(_) => crash "Validated ASCII bytes"
}

clock_numbers : Str, Str, I64 -> Try(List(U8), RfcRuleParts.Error)
clock_numbers = |part, text, limit| {
	var $result = []
	for value in text.split_on(",") {
		if $result.len() == 4096 {
			return Err(TooLarge)
		}
		bytes = value.to_utf8()
		if bytes.is_empty() or bytes.len() > 2 {
			return Err(Malformed(part))
		}
		var $number = 0.I64
		for byte in bytes {
			if byte < 48 or byte > 57 {
				return Err(Malformed(part))
			}
			$number = $number * 10 + byte.to_i64() - 48
		}
		if $number > limit {
			return Err(OutOfRange(part))
		}
		$result = $result.append($number.to_u8_wrap())
	}
	Ok($result)
}
