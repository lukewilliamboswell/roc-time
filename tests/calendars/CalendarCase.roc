import fuzz.Fuzz
import time.Calendar
import time.CalendarValue
import time.CalendarDate
import time.CivilDay
import time.JulianDate
import time.ClockTime
import time.LocalDateTime

# R06: full Julian coordinate range, overlap with Gregorian and explicit errors.
CalendarCase := { number : I64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(CalendarCase)
	generator_for = |_| Fuzz.map(
		Fuzz.map2(
			Fuzz.u8_in(0, 4),
			Fuzz.u64_in(0, 1568736804863),
			|choice, value| match choice {
				0 => -784369121962.I64
				1 => 784367682901.I64
				2 => 0.I64
				_ => U64.to_i64_wrap(value) - 784369121962
			},
		),
		|number| { number: number },
	)

	check : CalendarCase -> Fuzz.Outcome
	check = |input| {
		coordinate = CivilDay.from_day_number(input.number)
		validated = match JulianDate.from_civil_day(coordinate) {
			Ok(value) => value
			Err(_) => crash "Julian fixture range"
		}
		preserved = CalendarDate.from_julian(validated)
		if CalendarDate.to_civil_day(preserved) != coordinate or CalendarDate.calendar(preserved) != Julian {
			crash "Validated date conversion changed coordinate or calendar"
		}
		julian = match CalendarDate.from_civil_day(Julian, coordinate) {
			Ok(date) => date
			Err(_) => crash "R06 supported Julian coordinate rejected"
		}
		if CalendarDate.to_civil_day(julian) != coordinate or CalendarDate.calendar(julian) != Julian {
			crash "R06 Julian round trip or calendar identity"
		}
		if CalendarDate.from_fields(Julian, CalendarDate.to_fields(julian)) != Ok(julian) {
			crash "R06 Julian field reconstruction"
		}
		check_description(julian)
		converted = CalendarDate.in_calendar(julian, Gregorian)
		if input.number < -784353015833 or input.number > 784351576776 {
			if converted != Err(OutOfRange) {
				crash "R06 Gregorian provider range ignored"
			}
		} else {
			gregorian = match converted {
				Ok(date) => date
				Err(_) => crash "R06 shared coordinate rejected"
			}
			check_description(gregorian)
			# Map the existing full-range input to local fractions without changing
			# the curated decoder. Calendar conversion must preserve the label.
			micros = I64.rem_by(input.number + 784369121962, 86400000000)
			clock = match ClockTime.from_microseconds_since_midnight(micros) {
				Ok(label) => label
				Err(_) => crash "supported local clock rejected"
			}
			local = LocalDateTime.new(julian, clock)
			other = LocalDateTime.new(gregorian, clock)
			if !LocalDateTime.same_position(local, other) or local == other or
				LocalDateTime.in_calendar(local, Gregorian) != Ok(other) or
					LocalDateTime.clock(other) != clock {
				crash "local calendar conversion changed position or description"
			}
			if !CalendarDate.same_day(julian, gregorian) or julian == gregorian or
				CalendarDate.in_calendar(gregorian, Julian) != Ok(julian) {
				crash "R06 extent and description equality confused"
			}
		}
		# The four-year rule is independent of Gregorian century exceptions.
		fields = CalendarDate.to_fields(julian)
		if fields.year <= 2147483643 {
			shifted = match JulianDate.from_fields({ year: fields.year + 4, month: fields.month, day: fields.day }) {
				Ok(date) => date
				Err(_) => crash "R06 four-year recurrence of Julian fields"
			}
			if CivilDay.to_day_number(JulianDate.to_civil_day(shifted)) != input.number + 1461 {
				crash "R06 Julian four-year cycle width"
			}
		}
		unknown = input.number.to_str()
		if Calendar.from_name(unknown) != Err(UnsupportedCalendar(unknown)) {
			crash "R06 unsupported calendar substituted"
		}
		Fuzz.keep
	}
}

# R02/R14: independently count valid field dates within each month/year.
# This model asks the calendar constructor about every possible day, rather
# than computing the next month/year boundary like CalendarValue does.
check_description = |date| {
	fields = CalendarDate.to_fields(date)
	calendar = CalendarDate.calendar(date)
	year = match CalendarValue.year(calendar, fields.year) {
		Ok(value) => value
		Err(_) => crash "Valid description year"
	}
	month = match CalendarValue.month(calendar, fields.year, fields.month) {
		Ok(value) => value
		Err(_) => crash "Valid description month"
	}
	var $total = 0.I64
	var $selected = 0.I64
	var $m = 1.U8
	while $m <= 12 {
		var $d = 1.U8
		while $d <= 31 {
			match CalendarDate.from_fields(calendar, { year: fields.year, month: $m, day: $d }) {
				Ok(_) => {
					$total = $total + 1
					if $m == fields.month {
						$selected = $selected + 1
					}
				}
				Err(InvalidDay) => {}
				Err(_) => crash "Calendar model outside valid year"
			}
			$d = $d + 1
		}
		$m = $m + 1
	}
	for query in [{ value: year, width: $total, last: fields.year == 2147483647 }, { value: month, width: $selected, last: fields.year == 2147483647 and fields.month == 12 }] {
		match CalendarValue.local_bounds(query.value) {
			Err(OutOfRange) => if !query.last {
				crash "Description lost valid upper boundary"
			}
			Ok(bounds) => {
				width = CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(bounds.end))) - CivilDay.to_day_number(CalendarDate.to_civil_day(LocalDateTime.date(bounds.start)))
				if query.last or width != query.width {
					crash "Description differs from bounded field enumeration"
				}
			}
		}
	}
}
