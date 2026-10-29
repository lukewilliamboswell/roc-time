## Strict numeric protocol admission and independent resource laws. Requested
## byte traffic is not live/retained memory or a wall-clock bound.
ResourceMetrics := [].{
	read : Str, U64 -> Try(List(U64), [MalformedMetrics])
	read = |stderr, length| {
		fields = match stderr.split_on(" work=") {
			[_, raw] if raw.ends_with("\n") => raw.drop_suffix("\n").split_on(",")
			_ => return Err(MalformedMetrics)
		}
		if fields.len() != length {
			return Err(MalformedMetrics)
		}
		fields.map_try(
			|field| {
				if field.is_empty() or !field.to_utf8().all(|byte| byte >= '0' and byte <= '9') {
					return Err(MalformedMetrics)
				}
				U64.from_str(field).map_err(|_| MalformedMetrics)
			},
		)
	}

	within_growth : U64, U64 -> Bool
	within_growth = |small, large| {
		base = if (small == 0) 1 else small
		# Above this boundary, the mathematical bound exceeds U64.max, so
		# every representable large observation satisfies it without overflow.
		base > 144115188075855871 or large <= base * 128
	}

	failure_in_scope : Str, Str, Str -> Bool
	failure_in_scope = |stderr, before, after| match stderr.split_on(before) {
		[prefix, rest] if !prefix.contains("ROC_ASSERT_FAILED") => match rest.split_on("ROC_ASSERT_FAILED") {
			[between, .. as tail] => !between.contains(after) and Str.join_with(tail, "ROC_ASSERT_FAILED").contains(after)
			_ => Bool.False
		}
		_ => Bool.False
	}
}

expect ResourceMetrics.read("ROC_METRICS protocol=1 work=0,18446744073709551615\n", 2) == Ok([0, 18446744073709551615])
expect ResourceMetrics.read(" work=0,-1\n", 2) == Err(MalformedMetrics)
expect ResourceMetrics.read(" work=0,1\ntrailing", 2) == Err(MalformedMetrics)
expect ResourceMetrics.read(" work=0,1\n", 3) == Err(MalformedMetrics)
expect ResourceMetrics.within_growth(0, 128) and !ResourceMetrics.within_growth(0, 129)
expect ResourceMetrics.within_growth(18446744073709551615, 18446744073709551615)
expect ResourceMetrics.failure_in_scope("mark=3 x ROC_ASSERT_FAILED x mark=4 ", "mark=3 ", "mark=4 ")
expect !ResourceMetrics.failure_in_scope("ROC_ASSERT_FAILED mark=3 x mark=4 ", "mark=3 ", "mark=4 ")
expect !ResourceMetrics.failure_in_scope("mark=3 x mark=4 ROC_ASSERT_FAILED", "mark=3 ", "mark=4 ")

expect ResourceMetrics.failure_in_scope("mark=3 ROC_ASSERT_FAILED x ROC_ASSERT_FAILED mark=4 ", "mark=3 ", "mark=4 ")
