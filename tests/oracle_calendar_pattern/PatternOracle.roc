import time.CalendarPattern
import time.GregorianDate
import time.CivilDay

PatternOracle :: [].{
	run_args = |args| {
		if args.len() != 15 or at(args, 2) != "pattern" {
			crash "Invalid pattern oracle transport"
		}
		"${at(args, 1)}\t${observe(args.drop_first(3))}\n"
	}
	verify = |cases| {
		for case in cases {
			if observe(case.input) != case.expected {
				return Err(PatternOracleMismatch)
			}
		}
		Ok(cases.len())
	}
}

observe = |input| {
	anchor = match GregorianDate.from_fields({ year: integer(at(input, 0)), month: byte(at(input, 1)), day: byte(at(input, 2)) }) {
		Ok(value) => value
		Err(_) => crash "Invalid oracle anchor"
	}
	frequency = match at(input, 3) {
		"0" => Daily
		"1" => Weekly
		"2" => Monthly
		"3" => Yearly
		_ => crash "Invalid oracle frequency"
	}
	spec = {
		..CalendarPattern.defaults(frequency),
		interval: integer(at(input, 4)),
		week_start: weekday(byte(at(input, 5))),
		by_month: values(at(input, 7)).map(byte),
		by_month_day: values(at(input, 8)).map(small),
		by_year_day: values(at(input, 9)).map(medium),
		by_week_no: values(at(input, 10)).map(small),
		by_day: values(at(input, 11)).map(
			|part| {
				fields = part.split_on(":")
				{ ordinal: small(at(fields, 0)), weekday: weekday(byte(at(fields, 1))) }
			},
		),
	}
	pattern = match CalendarPattern.new(anchor, spec) {
		Ok(value) => value
		Err(_) => crash "Invalid oracle pattern"
	}
	index = match U64.from_str(at(input, 6)) {
		Ok(value) => value
		Err(_) => crash "Invalid oracle index"
	}
	frame = match CalendarPattern.period(pattern, index) {
		Ok(value) => value
		Err(_) => crash "Oracle period outside range"
	}
	start = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.start))
	end = CivilDay.to_day_number(GregorianDate.to_civil_day(frame.end))
	var current = start
	var bits = ""
	var fields = ["ok", start.to_str(), end.to_str()]
	while current < end {
		date = match GregorianDate.from_civil_day(CivilDay.from_day_number(current)) {
			Ok(value) => value
			Err(_) => crash "Oracle day outside range"
		}
		matched = match CalendarPattern.matches(pattern, index, date) {
			Ok(value) => value
			Err(_) => crash "Oracle match outside range"
		}
		bits = bits.concat(
			if matched {
				"1"
			} else {
				"0"
			},
		)
		if bits.count_utf8_bytes() == 128 {
			fields = fields.append(bits)
			bits = ""
		}
		current = current + 1
	}
	if !bits.is_empty() {
		fields = fields.append(bits)
	}
	Str.join_with(fields, "\t")
}

at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(_) => crash "Missing oracle field"
}

values = |text| if text == "-" {
	[]
} else {
	text.split_on(",")
}

integer = |text| match I64.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid oracle integer"
}

byte = |text| match U8.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid oracle byte"
}

small = |text| match I8.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid oracle selector"
}

medium = |text| match I16.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid oracle selector"
}

weekday = |n| match n {
	0 => Monday
	1 => Tuesday
	2 => Wednesday
	3 => Thursday
	4 => Friday
	5 => Saturday
	6 => Sunday
	_ => crash "Invalid oracle weekday"
}
