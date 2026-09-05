## Signed coordinate displacement on the POSIX axis, not physical SI elapsed time.
PosixDelta :: [Micros(I64)].{
	from_microseconds : I64 -> PosixDelta
	from_microseconds = |n| Micros(n)

	to_microseconds : PosixDelta -> I64
	to_microseconds = |Micros(n)| n

	is_eq : PosixDelta, PosixDelta -> Bool
	is_eq = |Micros(a), Micros(b)| a == b
}
