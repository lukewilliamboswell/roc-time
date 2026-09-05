## Signed coordinate displacement on the POSIX axis, not physical SI elapsed time.
PosixDelta :: [Micros(I64)].{
	from_microseconds : I64 -> PosixDelta
	from_microseconds = |n| Micros(n)

	to_microseconds : PosixDelta -> I64
	to_microseconds = |Micros(n)| n

	is_lt : PosixDelta, PosixDelta -> Bool
	is_lt = |Micros(a), Micros(b)| a < b

	is_lte : PosixDelta, PosixDelta -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b

	is_gt : PosixDelta, PosixDelta -> Bool
	is_gt = |Micros(a), Micros(b)| a > b

	is_gte : PosixDelta, PosixDelta -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b

	to_hash : PosixDelta, Hasher -> Hasher
	to_hash = |Micros(value), hasher| value.to_hash(hasher)

	to_inspect : PosixDelta -> Str
	to_inspect = |Micros(value)| "PosixDelta(${value.to_str()} microseconds)"

	is_eq : PosixDelta, PosixDelta -> Bool
	is_eq = |Micros(a), Micros(b)| a == b
}
