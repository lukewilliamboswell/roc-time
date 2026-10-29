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

	is_within_growth : { small : U64, large : U64 } -> Bool
	is_within_growth = |{ small, large }| {
		base = if (small == 0) 1 else small
		# Above this boundary, the mathematical bound exceeds U64.max, so
		# every representable large observation satisfies it without overflow.
		base > 144115188075855871 or large <= base * 128
	}

	has_failure_in_scope : { stderr : Str, before : Str, after : Str } -> Bool
	has_failure_in_scope = |{ stderr, before, after }| match stderr.split_on(before) {
		[prefix, rest] if !prefix.contains("ROC_ASSERT_FAILED") => match rest.split_on("ROC_ASSERT_FAILED") {
			[between, .. as tail] => !between.contains(after) and Str.join_with(tail, "ROC_ASSERT_FAILED").contains(after)
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Admit work counters through the full U64 range.
expect ResourceMetrics.read("ROC_METRICS protocol=1 work=0,18446744073709551615\n", 2) == Ok([0, 18446744073709551615])

## Reject signed work counters.
expect ResourceMetrics.read(" work=0,-1\n", 2) == Err(MalformedMetrics)

## Reject trailing metrics output.
expect ResourceMetrics.read(" work=0,1\ntrailing", 2) == Err(MalformedMetrics)

## Require the declared work-vector length.
expect ResourceMetrics.read(" work=0,1\n", 3) == Err(MalformedMetrics)

## Pin the independent growth allowance boundary.
expect ResourceMetrics.is_within_growth({
	small: 0,
	large: 128,
}) and !ResourceMetrics.is_within_growth({
	small: 0,
	large: 129,
})

## Avoid overflow when the growth bound exceeds U64.
expect ResourceMetrics.is_within_growth({
	small: 18446744073709551615,
	large: 18446744073709551615,
})

## Find an assertion between its trace marks.
expect ResourceMetrics.has_failure_in_scope({
	stderr: "mark=3 x ROC_ASSERT_FAILED x mark=4 ",
	before: "mark=3 ",
	after: "mark=4 ",
})

## Reject an assertion before the measured region.
expect !ResourceMetrics.has_failure_in_scope({
	stderr: "ROC_ASSERT_FAILED mark=3 x mark=4 ",
	before: "mark=3 ",
	after: "mark=4 ",
})

## Reject an assertion after the measured region.
expect !ResourceMetrics.has_failure_in_scope({
	stderr: "mark=3 x mark=4 ROC_ASSERT_FAILED",
	before: "mark=3 ",
	after: "mark=4 ",
})

## Allow repeated failures within the measured region.
expect ResourceMetrics.has_failure_in_scope({
	stderr: "mark=3 ROC_ASSERT_FAILED x ROC_ASSERT_FAILED mark=4 ",
	before: "mark=3 ",
	after: "mark=4 ",
})
