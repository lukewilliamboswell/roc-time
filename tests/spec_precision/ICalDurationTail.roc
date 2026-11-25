import fuzz.Solve
import time.Calendar
import time.ICalendar.Duration as ICalDuration
import time.PosixDelta

ICalDurationTail := [].{}

# The parser must reject coordinate tails that exceed the
# microsecond range only after adding all their fields. Fix the hour field
# one hour below the last whole hour, then search normalized second fields
# and minute fields up through 61. RFC 5545 §3.3.6 gives minutes no upper
# field bound. At this hour, all individual fields fit even at the cutoff.
# Zero proposals minimize minutes and then seconds in the search domain.
# https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.6
expect {
	max_seconds = I64.highest // 1000000
	hours = max_seconds // 3600 - 1
	tail_allowance = (max_seconds - hours * 3600).to_u16_try()?
	witness = Solve.find_near_within(
		{ minute: Solve.u16_in(0, 61), second: Solve.u16_in(0, 59) }.Solve,
		|{ minute, second }| (minute * 60 + second).gt(Solve.Uint.from_u16(tail_allowance)),
		[0, 0],
		1000,
	)?
	match witness {
		Found({ minute, second }) if minute.value() == 60 and second.value() == 55 => {
			m = minute.value()
			s = second.value()
			bad = "P1DT${hours.to_str()}H${m.to_str()}M${s.to_str()}S"
			good = "P1DT${hours.to_str()}H${m.to_str()}M${(s - 1).to_str()}S"
			value = ICalDuration.parse(good)?
			match ICalDuration.to_duration(value) {
				Calendar(spec) =>
					Calendar.Delta.to_components(spec.delta) == { years: 0, months: 0, days: 1 } and
						PosixDelta.to_microseconds(spec.tail) == max_seconds * 1000000 and
							ICalDuration.parse(bad) == Err(OutOfRange)
				Coordinate(_) => False
			}
		}
		_ => False
	}
}
