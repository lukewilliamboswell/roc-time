## Signed coordinate displacement on the POSIX axis, not physical SI elapsed time.
PosixDelta :: [Micros(I64)].{
	## Construct a signed coordinate displacement in whole microseconds.
	## Every I64 value is accepted; negative values move toward earlier positions.
	from_microseconds : I64 -> PosixDelta
	from_microseconds = |n| Micros(n)

	## Read the signed microsecond displacement. It carries no date or epoch.
	to_microseconds : PosixDelta -> I64
	to_microseconds = |Micros(n)| n

	## Whether the first of two signed POSIX displacements precedes the second in their numeric order.
	is_lt : PosixDelta, PosixDelta -> Bool
	is_lt = |Micros(a), Micros(b)| a < b

	## Whether the first of two signed POSIX displacements precedes or equals the second.
	is_lte : PosixDelta, PosixDelta -> Bool
	is_lte = |Micros(a), Micros(b)| a <= b

	## Whether the first of two signed POSIX displacements follows the second in their numeric order.
	is_gt : PosixDelta, PosixDelta -> Bool
	is_gt = |Micros(a), Micros(b)| a > b

	## Whether the first of two signed POSIX displacements follows or equals the second.
	is_gte : PosixDelta, PosixDelta -> Bool
	is_gte = |Micros(a), Micros(b)| a >= b

	## Hash signed POSIX displacements consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : PosixDelta, Hasher -> Hasher
	to_hash = |Micros(value), hasher| value.to_hash(hasher)

	## Return a concise diagnostic description of these signed POSIX displacements.
	## Use explicit conversions or text serialization when storing or exchanging data.
	to_inspect : PosixDelta -> Str
	to_inspect = |Micros(value)| "PosixDelta(${value.to_str()} microseconds)"

	## Equality of signed POSIX displacements; values of other temporal domains must be converted explicitly.
	is_eq : PosixDelta, PosixDelta -> Bool
	is_eq = |Micros(a), Micros(b)| a == b
}
