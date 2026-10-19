## Strict observation transport for the composed recurrence corpus. Each case
## contains six fields per occurrence: source minute, UTC start/end minute,
## ending kind and start/end gap adjustments. Rows are compared in their original order.
LocalOracle := [].{
	verify : Str, Str -> Try({}, [Malformed, MissingOrChanged])
	verify = |expected, actual| {
		if !well_formed(expected) or !well_formed(actual) {
			return Err(Malformed)
		}
		if expected.trim() == actual.trim() {
			Ok({})
		} else {
			Err(MissingOrChanged)
		}
	}

	controls : Str -> Try({}, [FailedControl])
	controls = |expected| {
		# Alter valid observations through the same comparison the gate uses.
		# This remains active in optimized code; it does not depend on expect.
		lines = expected.trim().split_on("\n")
		missing = Str.join_with(lines.drop_first(1), "\n")
		wrong = Str.join_with(expected.split_on(":0:"), ":1:")
		if verify(expected, expected) != Ok({}) or verify(expected, missing) != Err(MissingOrChanged) or verify(expected, wrong) != Err(MissingOrChanged) or verify(expected, "malformed") != Err(Malformed) {
			Err(FailedControl)
		} else {
			Ok({})
		}
	}
}

well_formed = |text| {
	lines = text.trim().split_on("\n")
	!lines.is_empty() and lines.all(
		|line| match line.split_on("\t") {
			[name, rows] => name.split_on("/").len() == 4 and name.split_on("/").all(|n| I64.from_str(n).is_ok()) and
				rows.split_on(",").all(
					|row| match row.split_on(":") {
						[source, start, end, ending, adjustment, end_adjustment] => I64.from_str(source).is_ok() and I64.from_str(start).is_ok() and I64.from_str(end).is_ok() and (ending == "0" or ending == "1" or ending == "2" or ending == "3") and (adjustment == "0" or adjustment == "1") and (end_adjustment == "0" or end_adjustment == "1")
						_ => Bool.False
					},
				)
			_ => Bool.False
		},
	)
}

expect LocalOracle.verify("30/0/0/0\t90:90:150:0:0:0\n", "30/0/0/0\t90:90:150:0:0:0\n") == Ok({})
expect LocalOracle.verify("30/0/0/0\t90:90:150:0:0:0\n", "") == Err(Malformed)
expect LocalOracle.verify("30/0/0/0\t90:90:150:0:0:0\n", "30/0/0/0\t90:91:150:0:0:0\n") == Err(MissingOrChanged)
expect LocalOracle.verify("30/0/0/0\t90:90:150:0:0:0\n", "30/0/0/0\t90:90:150:0:0:garbage\n") == Err(Malformed)
