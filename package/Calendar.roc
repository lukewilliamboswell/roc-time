## Supported proleptic calendar profiles. No historical reform is inferred.
Calendar := [Gregorian, Julian].{
	is_eq : Calendar, Calendar -> Bool
	is_eq = |a, b| to_name(a) == to_name(b)

	to_hash : Calendar, Hasher -> Hasher
	to_hash = |calendar, hasher| to_name(calendar).to_hash(hasher)

	to_inspect : Calendar -> Str
	to_inspect = |calendar| "Calendar(${to_name(calendar)})"
	from_name : Str -> Try(Calendar, [UnsupportedCalendar(Str), ..])
	from_name = |name| {
		match name {
			"gregorian" => Ok(Gregorian)
			"julian" => Ok(Julian)
			_ => Err(UnsupportedCalendar(name))
		}
	}

	to_name : Calendar -> Str
	to_name = |calendar| match calendar {
		Gregorian => "gregorian"
		Julian => "julian"
	}
}
