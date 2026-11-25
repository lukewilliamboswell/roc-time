## Internal January anchor for date conversion and week numbering.
GregorianYear := [].{
	# Counts complete years before January 1 relative to Gregorian 1970-01-01.
	# Callers constrain year to [-2147483649, 2147483649], including adjacent
	# years used only to calculate weeks. Shifting by whole Gregorian cycles
	# preserves every leap-year divisor and makes the quotient inputs nonnegative.
	start : I64 -> I64
	start = |year| {
		# The least whole-cycle shift that covers the year before I32.lowest.
		cycles = 5368710.I64
		previous = I64.plus_wrap(year, cycles * 400 - 1).to_u64_wrap()
		# previous is below 2^33 and the accumulated days below 2^42.
		# The common-year total alone covers the century correction.
		common_days = U64.times_wrap(365, previous)
		leap_days = previous // 4 - previous // 100 + previous // 400
		days = U64.plus_wrap(common_days, leap_days)
		I64.minus_wrap(days.to_i64_wrap(), cycles * 146097 + 719162)
	}
}
