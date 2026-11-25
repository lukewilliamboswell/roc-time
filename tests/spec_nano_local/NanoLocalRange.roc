import fuzz.Solve
import time.Nanosecond.LocalDateTime as NanoLocalDateTime

NanoLocalRange := [].{}

# A table exporter accepts validated Gregorian labels when their
# nominal day and clock fit the signed I64 carrier. Floor-dividing each limit
# into 86,400-second days identifies a partial day at each edge.
day_nanoseconds = 86_400_000_000_000.U64

first_day = -106_752.I64

last_day = 106_751.I64

first_clock = 763_145_224_192.U64

last_clock = 85_636_854_775_807.U64

# Each remainder certifies the floor quotient and the anchored count. The
# first midnight is below I64.lowest even though some of that day's clocks fit.
expect {
	scale = day_nanoseconds.to_i128()
	first_midnight = first_day.to_i128() * scale
	last_midnight = last_day.to_i128() * scale
	0 < first_clock and first_clock < day_nanoseconds and
		0 < last_clock and last_clock < day_nanoseconds and
			first_midnight + first_clock.to_i128() == I64.lowest.to_i128() and
				last_midnight + last_clock.to_i128() == I64.highest.to_i128()
}

# For every clock on each boundary day, measure the displacement from the
# representable endpoint. This avoids the out-of-range midnight intermediate.
# Production instead calculates the entire scalar in I128 before narrowing.
expect Solve.prove_within(
	Solve.u64_in(0, day_nanoseconds - 1),
	|clock| {
		first = Solve.Uint.from_u64(first_clock)
		last = Solve.Uint.from_u64(last_clock)
		from_first = clock.minus_signed(first)
		from_last = clock.minus_signed(last)
		Solve.all([
			Solve.Uint.from_i64(I64.lowest).plus_overflows_signed(from_first).iff(clock.lt(first)),
			Solve.Uint.from_i64(I64.highest).plus_overflows_signed(from_last).iff(clock.gt(last)),
		])
	},
	1000,
) == Ok(Proved)

# Construct labels directly rather than obtaining test inputs from the decoder.
# The dates are the proleptic Gregorian labels at the two civil-day quotients
# relative to 1970-01-01. Adjacent valid labels keep their precision when export
# fails, including the nanosecond immediately before the first encodable label.
expect {
	var $valid = Bool.True
	for (text, day, encoded) in [
		("1677-09-21T00:12:43.145224191", first_day, Err(OutOfRange)),
		("1677-09-21T00:12:43.145224192", first_day, Ok(I64.lowest)),
		("2262-04-11T23:47:16.854775807", last_day, Ok(I64.highest)),
		("2262-04-11T23:47:16.854775808", last_day, Err(OutOfRange)),
	] {
		label = NanoLocalDateTime.parse_gregorian(text)?
		$valid = $valid and label.date().to_civil_day().to_day_number() == day and
			label.to_gregorian_text() == Ok(text) and label.to_gregorian_local_nanoseconds() == encoded
	}
	$valid
}
