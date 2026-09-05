## A civil-day coordinate: zero labels Gregorian 1970-01-01.
## This is not a timestamp, a UTC midnight, or an elapsed quantity.
CivilDay :: [Day(I64)].{
	from_day_number : I64 -> CivilDay
	from_day_number = |value| Day(value)

	to_day_number : CivilDay -> I64
	to_day_number = |Day(value)| value

	is_lt : CivilDay, CivilDay -> Bool
	is_lt = |Day(a), Day(b)| a < b

	is_lte : CivilDay, CivilDay -> Bool
	is_lte = |Day(a), Day(b)| a <= b

	is_gt : CivilDay, CivilDay -> Bool
	is_gt = |Day(a), Day(b)| a > b

	is_gte : CivilDay, CivilDay -> Bool
	is_gte = |Day(a), Day(b)| a >= b

	to_hash : CivilDay, Hasher -> Hasher
	to_hash = |Day(value), hasher| value.to_hash(hasher)

	to_inspect : CivilDay -> Str
	to_inspect = |Day(value)| "CivilDay(${value.to_str()})"

	is_eq : CivilDay, CivilDay -> Bool
	is_eq = |Day(a), Day(b)| a == b

	compare : CivilDay, CivilDay -> [LT, EQ, GT]
	compare = |Day(a), Day(b)| {
		if a < b {
			LT
		} else if a > b {
			GT
		} else {
			EQ
		}
	}
}
