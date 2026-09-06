import fuzz.Fuzz
import time.EdtfDate
import time.OffsetTimestamp
import time.CalendarValue
import time.QualifiedCalendarValue
import time.CalendarDate
import time.LocalDateTime
import time.ClockTime
import time.FixedOffset
import time.GregorianDate
import time.PosixBoundary

# R02/R13/R14: generated valid Gregorian dates in 1900..2100, supplied EDTF
# year/month/day resolution and whole qualifiers; complete offset timestamps
# with 0..6 fractional digits. The date oracle counts whole years/months using
# the Gregorian divisibility law, independently of CalendarDate conversions.
InterchangeCase := { year : U16, month : U8, day : U8, precision : U8, qualifier : U8, seconds : U32, fraction : U32, digits : U8, offset : I16 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(InterchangeCase)
	generator_for = |_| { year: Fuzz.map(Fuzz.u64_in(1900, 2100), |n| n.to_u16_wrap()), month: Fuzz.u8_in(1, 12), day: Fuzz.u8_in(0, 30), precision: Fuzz.u8_in(0, 2), qualifier: Fuzz.u8_in(0, 3), seconds: Fuzz.map(Fuzz.u64_in(0, 86399), |n| n.to_u32_wrap()), fraction: Fuzz.map(Fuzz.u64_in(0, 999999), |n| n.to_u32_wrap()), digits: Fuzz.u8_in(0, 6), offset: Fuzz.map(Fuzz.u64_in(0, 2878), |n| (n.to_i64_wrap() - 1439).to_i16_wrap()) }.Fuzz
	check : InterchangeCase -> Fuzz.Outcome
	check = |input| {
		day = 1 + input.day % month_days(input.year, input.month)
		date_text = "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}-${pad(day.to_u64(), 2)}"
		check_edtf(input, day, date_text)
		check_timestamp(input, day, date_text)
		check_malformed(input, date_text)
		Fuzz.Outcome.Keep
	}
}

month_days = |year, month| if month == 2 {
	if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) {
		29.U8
	} else {
		28
	}
} else if [4.U8, 6, 9, 11].contains(month) {
	30
} else {
	31
}

pad = |number, width| {
	raw = number.to_str()
	var result = raw
	while result.count_utf8_bytes() < width {
		result = "0${result}"
	}
	result
}

check_edtf = |input, day, date_text| {
	base = match input.precision {
		0 => input.year.to_str()
		1 => "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}"
		_ => date_text
	}
	suffix = match input.qualifier {
		0 => ""
		1 => "?"
		2 => "~"
		_ => "%"
	}
	source = "${base}${suffix}"
	parsed = match EdtfDate.parse(source) {
		Ok(value) => value
		Err(_) => crash "Generated valid EDTF date rejected"
	}
	if EdtfDate.to_text(parsed) != source or EdtfDate.parse(EdtfDate.to_text(parsed)) != Ok(parsed) {
		crash "EDTF canonical serialization changed supplied resolution or qualifier"
	}
	description = EdtfDate.description(parsed)
	value = QualifiedCalendarValue.described_value(description)
	expected_resolution = match input.precision {
		0 => Year
		1 => Month
		_ => Day
	}
	fields = CalendarDate.to_fields(LocalDateTime.date(CalendarValue.start_label(value)))
	if CalendarValue.resolution(value) != expected_resolution or fields.year != input.year.to_i64() or
		fields.month != (
			if input.precision == 0 {
				1
			} else {
				input.month
			}
		) or
			fields.day != (
				if input.precision < 2 {
					1
				} else {
					day
				}
			) {
		crash "EDTF parsed fields differ from generated calendar description"
	}
	expected_qualifications = match input.qualifier {
		0 => []
		1 => [{ scope: Whole, qualifier: Uncertain }]
		2 => [{ scope: Whole, qualifier: Approximate }]
		_ => [{ scope: Whole, qualifier: UncertainApproximate }]
	}
	if QualifiedCalendarValue.qualifications(description) != expected_qualifications or EdtfDate.from_description(description) != Ok(parsed) {
		crash "EDTF native adapter lost qualifier facts"
	}
}

check_timestamp = |input, day, date_text| {
	var scale = 1.U32
	var count = 0.U8
	while count < input.digits {
		scale = scale * 10
		count = count + 1
	}
	fraction = input.fraction % scale
	fraction_text = if input.digits == 0 {
		""
	} else {
		".${pad(fraction.to_u64(), input.digits.to_u64())}"
	}
	h = input.seconds // 3600
	m = (input.seconds // 60) % 60
	s = input.seconds % 60
	clock_text = "${pad(h.to_u64(), 2)}:${pad(m.to_u64(), 2)}:${pad(s.to_u64(), 2)}${fraction_text}"
	magnitude = if input.offset < 0 {
		-input.offset
	} else {
		input.offset
	}
	sign = if input.offset < 0 {
		"-"
	} else {
		"+"
	}
	numeric = "${sign}${pad((magnitude // 60).to_u64_wrap(), 2)}:${pad((magnitude % 60).to_u64_wrap(), 2)}"
	# Alternate asserted offsets and the two UTC spellings. -00:00 records
	# unknown local offset like Z; +00:00 retains an asserted zero offset.
	unasserted = input.qualifier < 2
	suffix = if unasserted {
		if input.qualifier == 0 {
			"Z"
		} else {
			"-00:00"
		}
	} else {
		numeric
	}
	source = "${date_text}T${clock_text}${suffix}"
	canonical = "${date_text}T${clock_text}${
		if unasserted {
			"Z"
		} else {
			numeric
		}
	}"
	parsed = match OffsetTimestamp.parse(source) {
		Ok(value) => value
		Err(_) => crash "Generated valid offset timestamp rejected"
	}
	if OffsetTimestamp.to_text(parsed) != canonical or OffsetTimestamp.parse(canonical) != Ok(parsed) {
		crash "Timestamp canonical serialization changed semantic parts"
	}
	parts = OffsetTimestamp.parts(parsed)
	expected_offset = if unasserted {
		UnassertedUtc
	} else {
		Asserted(FixedOffset.from_seconds(input.offset.to_i32() * 60))
	}
	fields = GregorianDate.to_fields(parts.date)
	clock = ClockTime.to_fields(parts.clock)
	micros = fraction * (1000000 // scale)
	if fields != { year: input.year.to_i64(), month: input.month, day } or
		clock != { hour: h.to_u8_wrap(), minute: m.to_u8_wrap(), second: s.to_u8_wrap(), microsecond: micros } or
			parts.fraction_digits != input.digits or parts.offset != expected_offset or OffsetTimestamp.new(parts) != Ok(parsed) {
		crash "Timestamp fields differ from generated input"
	}
	var days = 0.I64
	var year = 1900.U16
	while year < input.year {
		days = days + (
			if month_days(year, 2) == 29 {
				366
			} else {
				365
			}
		)
		year = year + 1
	}
	var month = 1.U8
	while month < input.month {
		days = days + month_days(input.year, month).to_i64()
		month = month + 1
	}
	# 1900-01-01 is 25567 whole days before the POSIX epoch (70 ordinary
	# years plus 17 leap days); all arithmetic stays within this bounded domain.
	elapsed_days = days + day.to_i64() - 1 - 25567
	offset_seconds = if unasserted {
		0.I64
	} else {
		input.offset.to_i64() * 60
	}
	expected = (elapsed_days * 86400 + input.seconds.to_i64() - offset_seconds) * 1000000 + micros.to_i64()
	if OffsetTimestamp.boundary(parsed) != Ok(PosixBoundary.from_microseconds(expected)) or
		OffsetTimestamp.from_boundary(PosixBoundary.from_microseconds(expected), expected_offset, input.digits) != Ok(parsed) {
		crash "Timestamp boundary differs from independent Gregorian day count"
	}
}

# Mutations remain in the property's domain: ordinary structured public failures
# must be observed rather than discarded by the harness.
check_malformed = |input, date_text| {
	invalid_day = month_days(input.year, input.month) + 1
	invalid_date = "${input.year.to_str()}-${pad(input.month.to_u64(), 2)}-${pad(invalid_day.to_u64(), 2)}"
	if EdtfDate.parse(invalid_date) != Err(Malformed) or EdtfDate.parse("${input.year.to_str()}-") != Err(Incomplete) {
		crash "EDTF invalid date or incomplete prefix misclassified"
	}
	if OffsetTimestamp.parse("${invalid_date}T00:00:00Z") != Err(InvalidDate) or
		OffsetTimestamp.parse("${date_text}T00:00:00+24:00") != Err(InvalidOffset) or
			OffsetTimestamp.parse("${date_text}T00:00:00.0000000Z") != Err(UnsupportedPrecision) or
				OffsetTimestamp.parse("${date_text}T23:59:60Z") != Err(UnsupportedLeapSecond) {
		crash "Timestamp malformed fields or unsupported precision misclassified"
	}
}
