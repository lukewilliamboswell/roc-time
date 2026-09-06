import fuzz.Fuzz
import time.CalendarValue
import time.CalendarDate
import time.FixedOffset
import time.PosixBoundary
import time.PosixSpan
import time.Coverage
import time.ZoneRules

# R02/R07/R13–R14: bounded decimal grids, full-day carries and synthetic preimages.
# The oracle uses integer grid widths and two explicitly known offset segments;
# it neither calls CalendarValue.local_bounds nor the resolver to form expectations.
DescriptionCase := { number : U64, digits : U8, gap : Bool }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(DescriptionCase)
	generator_for = |_| { number: Fuzz.u64_in(0, 86399999999), digits: Fuzz.u8_in(1, 6), gap: Fuzz.map(Fuzz.u8_in(0, 1), |n| n == 1) }.Fuzz
	check : DescriptionCase -> Fuzz.Outcome
	check = |input| {
		date = match epoch_date(input.digits) {
			Ok(value) => value
			Err(_) => crash "Valid epoch date"
		}
		number = input.number.to_i64_wrap()
		h = (number // 3600000000).to_u8_wrap()
		m = I64.mod_by(number // 60000000, 60).to_u8_wrap()
		s = I64.mod_by(number // 1000000, 60).to_u8_wrap()
		var width = 1000000.I64
		var index = 0.U8
		while index < input.digits {
			width = width // 10
			index = index + 1
		}
		fraction = (I64.mod_by(number, 1000000) // width).to_u32_wrap()
		value = match CalendarValue.fractional_second(date, { hour: h, minute: m, second: s }, { value: fraction, digits: input.digits }) {
			Ok(found) => found
			Err(_) => crash "Valid decimal grid rejected"
		}
		start = (number // width) * width
		check_bounds(value, start, width)
		hour = match CalendarValue.hour(date, h) {
			Ok(found) => found
			Err(_) => crash "Valid hour"
		}
		minute = match CalendarValue.minute(date, h, m) {
			Ok(found) => found
			Err(_) => crash "Valid minute"
		}
		second = match CalendarValue.second(date, h, m, s) {
			Ok(found) => found
			Err(_) => crash "Valid second"
		}
		check_bounds(hour, (number // 3600000000) * 3600000000, 3600000000)
		check_bounds(minute, (number // 60000000) * 60000000, 60000000)
		check_bounds(second, (number // 1000000) * 1000000, 1000000)
		check_bounds(CalendarValue.day(date), 0, 86400000000)
		if CalendarValue.resolution(value) != Fraction(input.digits) or CalendarValue.resolution(second) != Second {
			crash "Description lost resolution"
		}
		# Two-second jump around the entire decimal cell. A fold has exactly
		# two disjoint copies; reversing the offsets makes the cell absent.
		initial = if input.gap {
			0.I32
		} else {
			2.I32
		}
		after = 2 - initial
		rules = match ZoneRules.new_bounded("Synthetic/Description", "v1", span(start - 4000000, start + 4000000), FixedOffset.from_seconds(initial), [{ at: point(start - 1000000), offset: FixedOffset.from_seconds(after) }], { minimum: 0, maximum: 2 }) {
			Ok(found) => found
			Err(_) => crash "Valid synthetic rules"
		}
		cursor = match CalendarValue.selection_cursor(value, rules) {
			Ok(found) => found
			Err(_) => crash "Valid description selection"
		}
		first = match ZoneRules.SelectionCursor.collect(cursor, { max_segments: 0, max_members: 2 }) {
			Ok(found) => found
			Err(_) => crash "Zero-work selection"
		}
		var resumed = match first.status {
			Limited(progress) => progress.cursor
			Complete(_) => crash "Zero budget must remain incomplete"
		}
		var result = Coverage.empty
		var done = Bool.False
		var calls = 0.U64
		while calls < 4 and !done {
			batch = match ZoneRules.SelectionCursor.collect(resumed, { max_segments: 1, max_members: 2 }) {
				Ok(found) => found
				Err(_) => crash "Bounded selection failed"
			}
			match batch.status {
				Complete(coverage) => {
					result = coverage
					done = Bool.True
				}
				Limited(progress) => {
					resumed = progress.cursor
				}
			}
			calls = calls + 1
		}
		expected = if input.gap {
			Coverage.empty
		} else {
			Coverage.from_spans([span(start - 2000000, start - 2000000 + width), span(start, start + width)])
		}
		if !done or result != expected {
			crash "Calendar selection differs from independent two-segment preimage"
		}
		Fuzz.Outcome.Keep
	}
}

check_bounds = |value, start, width| {
	bounds = match CalendarValue.local_bounds(value) {
		Ok(found) => found
		Err(_) => crash "Valid civil bounds"
	}
	zero = FixedOffset.from_seconds(0)
	if FixedOffset.resolve(zero, bounds.start) != Ok(point(start)) or FixedOffset.resolve(zero, bounds.end) != Ok(point(start + width)) {
		crash "Calendar description differs from decimal grid"
	}
}

point = |number| PosixBoundary.from_microseconds(number)

span = |start, end| match PosixSpan.new(point(start), point(end)) {
	Ok(value) => value
	Err(_) => crash "Nonempty oracle span"
}

epoch_date = |_digits| CalendarDate.from_fields(Gregorian, { year: 1970, month: 1, day: 1 })
