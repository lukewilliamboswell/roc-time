## A local clock label at microsecond precision, without a date, zone or scale.
ClockTime :: [Micros(I64)].{
	Fields : { hour : U8, minute : U8, second : U8, microsecond : U32 }

	from_fields : Fields -> Try(ClockTime, [InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidMicrosecond, ..])
	from_fields = |fields| {
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
		if fields.microsecond > 999999 {
			return Err(InvalidMicrosecond)
		}
		Ok(Micros(fields.hour.to_i64() * 3600000000 + fields.minute.to_i64() * 60000000 + fields.second.to_i64() * 1000000 + fields.microsecond.to_i64()))
	}

	from_microseconds_since_midnight : I64 -> Try(ClockTime, [OutOfRange, ..])
	from_microseconds_since_midnight = |number| {
		if number < 0 or number >= 86400000000 {
			Err(OutOfRange)
		} else {
			Ok(Micros(number))
		}
	}

	to_microseconds_since_midnight : ClockTime -> I64
	to_microseconds_since_midnight = |Micros(number)| number

	to_fields : ClockTime -> Fields
	to_fields = |Micros(number)| {
		# The opaque constructor bounds number to one nonnegative nominal day.
		{
			hour: I64.div_trunc_by(number, 3600000000).to_u8_wrap(),
			minute: I64.rem_by(I64.div_trunc_by(number, 60000000), 60).to_u8_wrap(),
			second: I64.rem_by(I64.div_trunc_by(number, 1000000), 60).to_u8_wrap(),
			microsecond: I64.rem_by(number, 1000000).to_u32_wrap(),
		}
	}

	is_eq : ClockTime, ClockTime -> Bool
	is_eq = |Micros(a), Micros(b)| a == b
	is_lt : ClockTime, ClockTime -> Bool
	is_lt = |Micros(a), Micros(b)| a < b
	is_lte : ClockTime, ClockTime -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b
	is_gt : ClockTime, ClockTime -> Bool
	is_gt = |Micros(a), Micros(b)| a > b
	is_gte : ClockTime, ClockTime -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b
	to_hash : ClockTime, Hasher -> Hasher
	to_hash = |Micros(number), hasher| number.to_hash(hasher)
	to_inspect : ClockTime -> Str
	to_inspect = |Micros(number)| "ClockTime(${number.to_str()} microseconds since local midnight)"

	expect from_fields({ hour: 24, minute: 0, second: 0, microsecond: 0 }) == Err(InvalidHour)
	expect from_fields({ hour: 0, minute: 60, second: 0, microsecond: 0 }) == Err(InvalidMinute)
	expect from_fields({ hour: 23, minute: 59, second: 60, microsecond: 0 }) == Err(UnsupportedLeapSecond)
	expect from_fields({ hour: 0, minute: 0, second: 61, microsecond: 0 }) == Err(InvalidSecond)
	expect from_fields({ hour: 0, minute: 0, second: 0, microsecond: 1000000 }) == Err(InvalidMicrosecond)
	expect from_microseconds_since_midnight(-1) == Err(OutOfRange)
	expect from_microseconds_since_midnight(86400000000) == Err(OutOfRange)

	# Independent bounded odometer model: enumerate all seconds by carrying
	# fields, rather than using the production multiplication/division formulas.
	# Fractional endpoints exercise both sides of every second boundary.
	expect {
		var number = 0.I64
		var hour = 0.U8
		var valid = Bool.True
		while hour < 24 {
			var minute = 0.U8
			while minute < 60 {
				var second = 0.U8
				while second < 60 {
					for microsecond in [0.U32, 1, 999999] {
						fields = { hour, minute, second, microsecond }
						value = from_fields(fields)?
						valid = valid and to_fields(value) == fields and
							from_microseconds_since_midnight(number + microsecond.to_i64()) == Ok(value)
					}
					number = number + 1000000
					second = second + 1
				}
				minute = minute + 1
			}
			hour = hour + 1
		}
		valid and number == 86400000000
	}
}
