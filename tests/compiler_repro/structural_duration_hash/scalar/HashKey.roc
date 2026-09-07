import time.TimedOccurrence
import time.PosixDelta
import time.CalendarDelta

HashKey :: { duration : TimedOccurrence.Duration }.{
	new : I64 -> HashKey
	new = |n| { duration: Coordinate(PosixDelta.from_microseconds(n)) }
	is_eq : HashKey, HashKey -> Bool
	is_eq = |a, b| match (a.duration, b.duration) {
		(Coordinate(x), Coordinate(y)) => x == y
		(Calendar(x), Calendar(y)) => CalendarDelta.to_components(x.delta) == CalendarDelta.to_components(y.delta) and x.invalid_date == y.invalid_date and x.tail == y.tail and x.occurrence == y.occurrence and x.gap == y.gap
		_ => Bool.False
	}
	to_hash : HashKey, Hasher -> Hasher
	to_hash = |value, hasher| duration_key(value.duration).to_hash(hasher)
}

# Only the tail field differs from the failing derived-key expression.
duration_key = |duration| match duration {
	Coordinate(value) => Coordinate(PosixDelta.to_microseconds(value))
	Calendar(value) => Calendar({ components: CalendarDelta.to_components(value.delta), invalid_date: value.invalid_date, tail: PosixDelta.to_microseconds(value.tail) })
}
