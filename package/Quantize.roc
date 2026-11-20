import MicrosecondRounding

Quantize :: [].{
	# Callers supply 1000 or 10^12. The remainder and its double fit in the input type.
	to_microseconds : { value : n, divisor : n, rounding : MicrosecondRounding } -> Try(n, [Submicrosecond])
		where [n.div_trunc_by : n, n -> n, n.rem_by : n, n -> n, n.is_eq : n, n -> Bool, n.is_lt : n, n -> Bool, n.is_gt : n, n -> Bool, n.plus : n, n -> n, n.minus : n, n -> n, n.times : n, n -> n, n.negate : n -> n, n.from_numeral : Numeral -> Try(n, [InvalidNumeral(Str)])]
	to_microseconds = |{ value, divisor, rounding }| {
		q = value // divisor
		r = value % divisor
		if r == 0 {
			return Ok(q)
		}
		rounded = match rounding {
			RejectSubmicrosecond => return Err(Submicrosecond)
			TowardZero => q
			Floor => if r < 0 {
				q - 1
			} else {
				q
			}
			Ceiling => if r > 0 {
				q + 1
			} else {
				q
			}
			NearestTiesEven => {
				magnitude = if r < 0 {
					-r
				} else {
					r
				}
				if magnitude * 2 > divisor or (magnitude * 2 == divisor and q % 2 != 0) {
					q + if r < 0 {
						-1
					} else {
						1
					}
				} else {
					q
				}
			}
		}
		Ok(rounded)
	}
}
