import time.RfcDateRule
import time.DateRecurrence
import time.GregorianDate

DateOracle :: [].{
	run_args : List(Str) -> Str
	run_args = |args| {
		if args.len() != 9 or at(args, 2) != "rfc_date" {
			crash "Invalid RFC oracle transport"
		}
		"${at(args, 1)}\t${observe(args.drop_first(3))}\n"
	}
	verify = |cases| {
		var count = 0.U64
		for case in cases {
			if observe(case.input) != case.expected {
				return Err(Mismatch(count))
			}
			count = count + 1
		}
		Ok(count)
	}
}

observe = |input| {
	parts = { start: at(input, 0), rule: at(input, 1), inclusions: values(at(input, 2)), exclusions: values(at(input, 3)) }
	rule = match RfcDateRule.parse(parts) {
		Ok(value) => value
		Err(error) => crash "Oracle rule rejected: ${Str.inspect(error)}"
	}
	window = { start: date(at(input, 4)), end: date(at(input, 5)) }
	initial = match DateRecurrence.cursor(rule, window) {
		Ok(value) => value
		Err(_) => crash "Invalid oracle query"
	}
	var result = ["ok"]
	var batches = 0.U64
	var complete = False
	for outcome in DateRecurrence.Cursor.chunks(initial, { max_steps: 17, max_buffered: 366, max_occurrences: 1 }) {
		# Also exercise process-independent immutable resumptions, with one output
		# slot and a limit that regularly splits calendar periods.
		batch = match outcome {
			Ok(value) => value
			Err(_) => crash "Oracle query outside provider range"
		}
		if complete == True or batches >= 10000 {
			crash "Oracle chunk termination failure"
		}
		for value in batch.dates {
			result = result.append(display(value))
		}
		match batch.status {
			Complete => {
				complete = True
			}
			Limited(_) => {}
		}
		batches = batches + 1
	}
	if complete == False {
		crash "Oracle cursor did not finish"
	}
	Str.join_with(result, "\t")
}

values = |text| if text == "-" {
	[]
} else {
	[text]
}

at = |items, index| match List.get(items, index) {
	Ok(value) => value
	Err(_) => crash "Oracle transport arity"
}

date = |text| {
	value = match I64.from_str(text) {
		Ok(number) => number
		Err(_) => crash "Invalid oracle date"
	}
	year = I64.div_trunc_by(value, 10000)
	month = I64.mod_by(I64.div_trunc_by(value, 100), 100).to_u8_wrap()
	day = I64.mod_by(value, 100).to_u8_wrap()
	match GregorianDate.from_fields({ year, month, day }) {
		Ok(result) => result
		Err(_) => crash "Invalid oracle date fields"
	}
}

display = |value| {
	fields = GregorianDate.to_fields(value)
	"${fields.year.to_str()}${pad(fields.month)}${pad(fields.day)}"
}

pad = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}

expect DateOracle.verify([{ input: ["20240101", "FREQ=DAILY;COUNT=1", "-", "-", "20240101", "20240102"], expected: "ok\t20240101" }]) == Ok(1)
expect DateOracle.verify([{ input: ["20240101", "FREQ=DAILY;COUNT=1", "-", "-", "20240101", "20240102"], expected: "wrong" }]) == Err(Mismatch(0))
