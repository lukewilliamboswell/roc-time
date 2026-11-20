ClockLabel :: [].{
	Fields : { hour : U8, minute : U8, second : U8, fraction : U32 }
	FieldError : [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond]
	Error : [Malformed, Incomplete, TooLarge, UnsupportedPrecision, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond]
	validate : Fields -> Try({}, FieldError)
	validate = |fields| {
		if fields.hour > 23 {
			return Err(InvalidHour)
		}
		if fields.minute > 59 {
			return Err(InvalidMinute)
		}
		if fields.second == 60 {
			return Err(UnsupportedLeapSecond)
		}
		if fields.second > 59 {
			return Err(InvalidSecond)
		}
		Ok({})
	}
	parse : Str, U64 -> Try(Fields, Error)
	parse = |text, width| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		empty_fields = { hour: 0.U8, minute: 0.U8, second: 0.U8, fraction: 0.U32 }
		hour = pair(bytes, 0, empty_fields)?
		hour_fields = { ..empty_fields, hour }
		separator(bytes, 2, 58, hour_fields)?
		minute = pair(bytes, 3, hour_fields)?
		minute_fields = { ..hour_fields, minute }
		var $second = 0.U8
		var $fraction = 0.U32
		if bytes.len() > 5 {
			separator(bytes, 5, 58, minute_fields)?
			$second = pair(bytes, 6, minute_fields)?
			if bytes.len() > 8 {
				separator(bytes, 8, 46, { ..minute_fields, second: $second })?
				if bytes.len() == 9 {
					_ = validate({ ..minute_fields, second: $second })?
					return Err(Incomplete)
				}
				var $position = 9.U64
				while $position < bytes.len() {
					byte = match bytes.get($position) {
						Ok(found) => found
						Err(_) => return Err(Incomplete)
					}
					if byte < 48 or byte > 57 {
						return Err(Malformed)
					}
					if $position >= (9 + width) {
						return Err(UnsupportedPrecision)
					}
					$fraction = $fraction * 10 + (byte - 48).to_u32()
					$position = $position + 1
				}
				while $position < (9 + width) {
					$fraction = $fraction * 10
					$position = $position + 1
				}
			}
		}
		fields = { hour, minute, second: $second, fraction: $fraction }
		validate(fields)?
		Ok(fields)
	}

	to_text : Fields, U64 -> Str
	to_text = |fields, width| {
		base = "${two_digits(fields.hour)}:${two_digits(fields.minute)}:${two_digits(fields.second)}"
		if fields.fraction == 0 {
			return base
		}
		var $fraction = fields.fraction
		var $width = width
		while U32.rem_by($fraction, 10) == 0 {
			$fraction = U32.div_trunc_by($fraction, 10)
			$width = $width - 1
		}
		var $digits = $fraction.to_str()
		while $digits.count_utf8_bytes() < $width {
			$digits = "0${$digits}"
		}
		"${base}.${$digits}"
	}
}

pair : List(U8), U64, ClockLabel.Fields -> Try(U8, ClockLabel.Error)
pair = |bytes, position, completed_fields| {
	var $value = 0.U8
	for index in [position, position + 1] {
		byte = match bytes.get(index) {
			Ok(value) => value
			Err(_) => {
				_ = ClockLabel.validate(completed_fields)?
				# Completed higher fields take priority; only a missing second
				# digit can expose an impossible first-digit prefix here.
				if index > position {
					if position == 0 and $value > 2 {
						return Err(InvalidHour)
					}
					if position == 3 and $value > 5 {
						return Err(InvalidMinute)
					}
					if position == 6 and $value > 5 {
						return Err(InvalidSecond)
					}
				}
				return Err(Incomplete)
			}
		}
		if byte < 48 or byte > 57 {
			return Err(Malformed)
		}
		$value = $value * 10 + byte - 48
	}
	Ok($value)
}

separator : List(U8), U64, U8, ClockLabel.Fields -> Try({}, ClockLabel.Error)
separator = |bytes, position, expected, completed_fields| match bytes.get(position) {
	Ok(byte) => if byte == expected {
		Ok({})
	} else {
		Err(Malformed)
	}
	Err(_) => {
		_ = ClockLabel.validate(completed_fields)?
		Err(Incomplete)
	}
}

two_digits : U8 -> Str
two_digits = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}
