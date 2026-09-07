## A civil-day coordinate: zero labels Gregorian 1970-01-01.
## This is not a timestamp, a UTC midnight, or an elapsed quantity.
CivilDay :: [Day(I64)].{
	## Construct a civil-day coordinate from any signed I64 day number.
	## Zero is Gregorian 1970-01-01; negative numbers denote preceding days.
	## Converting to a calendar date can fail outside that calendar's range.
	from_day_number : I64 -> CivilDay
	from_day_number = |value| Day(value)

	## Read the signed count of civil days relative to Gregorian 1970-01-01.
	## It does not measure elapsed days on a resolved timeline.
	to_day_number : CivilDay -> I64
	to_day_number = |Day(value)| value

	## Whether the first of two civil-day coordinates precedes the second in their numeric order.
	is_lt : CivilDay, CivilDay -> Bool
	is_lt = |Day(a), Day(b)| a < b

	## Whether the first of two civil-day coordinates precedes or equals the second.
	is_lte : CivilDay, CivilDay -> Bool
	is_lte = |Day(a), Day(b)| a <= b

	## Whether the first of two civil-day coordinates follows the second in their numeric order.
	is_gt : CivilDay, CivilDay -> Bool
	is_gt = |Day(a), Day(b)| a > b

	## Whether the first of two civil-day coordinates follows or equals the second.
	is_gte : CivilDay, CivilDay -> Bool
	is_gte = |Day(a), Day(b)| a >= b

	## Hash civil-day coordinates consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : CivilDay, Hasher -> Hasher
	to_hash = |Day(value), hasher| value.to_hash(hasher)

	## Return a concise diagnostic description of these civil-day coordinates.
	## Use explicit conversions or text serialization when storing or exchanging data.
	to_inspect : CivilDay -> Str
	to_inspect = |Day(value)| "CivilDay(${value.to_str()})"

	## Equality of civil-day coordinates; values of other temporal domains must be converted explicitly.
	is_eq : CivilDay, CivilDay -> Bool
	is_eq = |Day(a), Day(b)| a == b

	## Compare two civil-day coordinates, returning LT, EQ or GT.
	## Calendar descriptions of the same civil day compare equal after conversion.
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
