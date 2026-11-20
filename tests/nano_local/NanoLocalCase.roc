import time.Calendar
import time.CivilDay
import time.NanoClockTime
import time.NanoLocalDateTime
import fuzz.Fuzz

NanoLocalCase := { number : I64 }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(NanoLocalCase)
	generator_for = |_| Fuzz.map(Fuzz.u64_in(0, U64.highest), |number| { number: number.to_i64_wrap() })
	check : NanoLocalCase -> Fuzz.Outcome
	check = |{ number }| {
		label = NanoLocalDateTime.from_gregorian_local_nanoseconds(number)
		actual_day = Calendar.Date.to_civil_day(label.date()).to_day_number().to_i128()
		actual_clock = label.clock().to_nanoseconds_since_midnight().to_i128()
		# A civil day is the unique half-open cell containing this signed count.
		start = actual_day * 86400000000000
		count = number.to_i128()
		if count < start or count >= start + 86400000000000 or count - start != actual_clock {
			crash "NanoLocalDateTime fields disagree with the civil day cell"
		}
		if label.to_gregorian_local_nanoseconds() != Ok(number) {
			crash "NanoLocalDateTime changes the source integer"
		}
		Fuzz.keep
	}
}
