import time.RfcTimedRule
import time.RfcDateTime
import time.TimedSchedule
import time.TimedOccurrence
import time.TimedRecurrence
import time.PosixBoundary
import time.PosixSpan
import time.PosixDelta

# R11–R12: public timed import, finite UTC rules, bounded resumptions.
TimedOracle :: [].{
	run_args : List(Str) -> Str
	run_args = |args| {
		if args.len() != 9 or at(args, 2) != "rfc_timed" {
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
	parsed = match RfcTimedRule.parse({ start: at(input, 0), rule: at(input, 1), mode: Utc, duration: "PT1S", inclusions: values(at(input, 2)), exclusions: values(at(input, 3)), periods: [] }) {
		Ok(value) => value
		Err(error) => crash "Timed oracle rule rejected: ${Str.inspect(error)}"
	}
	window = { start: label(at(input, 4)), end: label(at(input, 5)) }
	var cursor = match RfcTimedRule.schedule({}, parsed, window, Utc) {
		Ok(value) => value
		Err(_) => crash "Timed oracle window rejected"
	}
	var output = ["ok"]
	var calls = 0.U64
	while calls < 10000 {
		batch = match TimedSchedule.collect(cursor, { work: { max_steps: 17, max_buffered: 366, max_zone_segments: 2, max_zone_candidates: 1 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(_) => crash "Timed oracle execution failed"
		}
		for value in batch.occurrences {
			start = TimedOccurrence.start(value)
			if PosixSpan.coordinate_width(TimedOccurrence.span(value)) != Ok(PosixDelta.from_microseconds(1000000)) {
				crash "Timed oracle changed one-second duration"
			}
			output = output.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(start)).to_str())
		}
		match batch.status {
			Complete => return Str.join_with(output, "\t")
			Limited(progress) => {
				cursor = progress.cursor
			}
		}
		calls = calls + 1
	}
	crash "Timed oracle failed to terminate"
}

at = |items, index| match List.get(items, index) {
	Ok(value) => value
	Err(_) => crash "Oracle transport arity"
}

values = |text| if text == "-" {
	[]
} else {
	[text]
}

label = |text| match RfcDateTime.parse(text) {
	Ok(value) => RfcDateTime.local_label(value)
	Err(_) => crash "Invalid oracle timestamp"
}
expect TimedOracle.verify([{ input: ["20240101T090000Z", "FREQ=HOURLY;COUNT=1", "-", "-", "20240101T000000Z", "20240102T000000Z"], expected: "ok\t1704099600000000" }]) == Ok(1)
expect TimedOracle.verify([{ input: ["20240101T090000Z", "FREQ=HOURLY;COUNT=1", "-", "-", "20240101T000000Z", "20240102T000000Z"], expected: "wrong" }]) == Err(Mismatch(0))
