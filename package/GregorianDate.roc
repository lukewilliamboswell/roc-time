import CivilDay

## Proleptic Gregorian day, with astronomical years (0 means 1 BCE).
## Valid years are -2147483648 through 2147483647, inclusive.
## No timezone or resolved timeline is implied by a date.
##
## Example
##
## Create a date and read its fields. Invalid leap days return `InvalidDay`;
## year zero and negative years use astronomical numbering.
##
## ```roc
## import time.GregorianDate
##
## expect {
##     date = GregorianDate.from_fields({ year: 2024, month: 2, day: 29 })?
##     GregorianDate.to_fields(date).day == 29
## }
## expect {
##     invalid = GregorianDate.from_fields({ year: 2025, month: 2, day: 29 })
##     invalid == Err(InvalidDay)
## }
## ```
##
## Parse a form field or validate a typed literal. Canonical output keeps the
## calendar date; use a description type when supplied resolution matters.
##
## ```roc
## import time.GregorianDate
##
## expect {
##     due : GregorianDate
##     due = "2026-09-07"
##     GregorianDate.parse("2026-09-07") == Ok(due) and
##         GregorianDate.to_text(due) == "2026-09-07"
## }
## ```
##
## Examples assume a package dependency named `time`.
## Week queries use the accounting date as supplied: for example, 2021-01-01
## is Friday, ordinal day 1, in ISO week 53 of 2020. Group by both `week_year`
## and `week`; the Gregorian year alone does not identify an ISO week.
GregorianDate :: [Date({ year : I64, month : U8, day : U8 })].{
	## Astronomical year and one-based month/day fields for a Gregorian date.
	## Year zero means 1 BCE; from_fields validates combinations and provider range.
	Fields : { year : I64, month : U8, day : U8 }
	## Parsing failures distinguish unfinished input, malformed text, invalid calendar
	## fields, unsupported year range and input longer than the profile limit.
	Error : [Malformed, Incomplete, OutOfRange, InvalidMonth, InvalidDay, TooLarge]
	## Weekday names in Monday-through-Sunday order. They describe civil dates,
	## without a timezone or an elapsed-duration interpretation.
	Weekday : [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
	## ISO week-based year, week number (1..53) and weekday.
	## The week_year may differ from the ordinary calendar year near New Year.
	IsoWeekDate : { week_year : I64, week : U8, weekday : Weekday }

	## Native Gregorian full-date text, with no timezone or reduced resolution.
	## Years 0..9999 have four digits; negative years have a minus and at least
	## four magnitude digits; larger positive years have a plus and no padding.
	## Signed expanded years are a library extension, not an RFC 3339 claim.
	## Input longer than 64 UTF-8 bytes returns TooLarge; parsing work is bounded.
	## Incomplete means a valid unfinished prefix. Completed invalid fields and
	## impossible day prefixes (such as 1900-02-3) retain constructor errors.
	profile : Str
	profile = "native-gregorian-full-date-v1"

	## Build a decoder for one encoded string containing a Gregorian full date.
	## Return the validated date and unconsumed encoding state; distinguish
	## InvalidGregorianDate from failures of the outer Encoding.
	parser_for : encoding -> (state -> Try({ value : GregorianDate, rest : state }, [InvalidGregorianDate(Error), Encoding(err), ..]))
		where [encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err)]
	parser_for = |encoding| {
		Encoding : encoding
		|state| {
			parsed = match Encoding.parse_str(encoding, state) {
				Ok(value) => value
				Err(error) => return Err(Encoding(error))
			}
			match parse(parsed.value) {
				Ok(value) => Ok({ value, rest: parsed.rest })
				Err(error) => Err(InvalidGregorianDate(error))
			}
		}
	}

	## Build an encoder that writes this date as its canonical full-date string
	## using the supplied string encoding. Propagate errors from that encoding.
	encoder_for : encoding -> (GregorianDate, state -> Try(state, err))
		where [encoding.encode_str : Str, state -> Try(state, err)]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Support validated quoted date literals when the expected type is GregorianDate.
	## Invalid literals are rejected with BadQuotedBytes; use parse for runtime text.
	from_quote : Str -> Try(GregorianDate, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid GregorianDate literal: ${Str.inspect(error)}"))
	}

	## Parse a full Gregorian date using the declared native profile, such as
	## 2026-09-07. Signed expanded years are supported within the provider range.
	## Return structured errors for invalid dates, incomplete or malformed text,
	## and inputs beyond the profile limits.
	parse : Str -> Try(GregorianDate, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		size = bytes.len()
		if size == 0 {
			return Err(Incomplete)
		}
		first = byte_at(bytes, 0)
		negative = first == 45
		signed = negative or first == 43
		start = if signed {
			1.U64
		} else {
			0.U64
		}
		var $end = start
		var $magnitude = 0.I64
		while $end < size and byte_at(bytes, $end) >= 48 and byte_at(bytes, $end) <= 57 {
			# At most ten digits are accumulated, so multiplication fits I64.
			if $end - start < 10 {
				$magnitude = $magnitude * 10 + U8.to_i64(byte_at(bytes, $end) - 48)
			}
			$end = $end + 1
		}
		digits = $end - start
		if digits == 0 {
			return if $end == size {
				Err(Incomplete)
			} else {
				Err(Malformed)
			}
		}
		if !signed and digits > 4 {
			return Err(Malformed)
		}
		if signed and byte_at(bytes, start) == 48 and (first == 43 or digits > 4) {
			return Err(Malformed)
		}
		if digits > 10 {
			return Err(OutOfRange)
		}
		year = if negative {
			-($magnitude)
		} else {
			$magnitude
		}
		if year < -2147483648 or year > 2147483647 {
			return Err(OutOfRange)
		}
		minimum = if first == 43 {
			5.U64
		} else {
			4.U64
		}
		if digits < minimum {
			return if $end == size {
				Err(Incomplete)
			} else {
				Err(Malformed)
			}
		}
		if negative and $magnitude == 0 {
			return Err(Malformed)
		}
		if $end == size {
			return Err(Incomplete)
		}
		if byte_at(bytes, $end) != 45 {
			return Err(Malformed)
		}
		month_start = $end + 1
		if month_start == size {
			return Err(Incomplete)
		}
		month_first = byte_at(bytes, month_start)
		if month_first < 48 or month_first > 57 {
			return Err(Malformed)
		}
		if month_start + 1 == size {
			return if month_first <= 49 {
				Err(Incomplete)
			} else {
				Err(InvalidMonth)
			}
		}
		month_last = byte_at(bytes, month_start + 1)
		if month_last < 48 or month_last > 57 {
			return Err(Malformed)
		}
		month = (month_first - 48) * 10 + month_last - 48
		length = days_in_month(year, month)?
		separator = month_start + 2
		if separator == size {
			return Err(Incomplete)
		}
		if byte_at(bytes, separator) != 45 {
			return Err(Malformed)
		}
		day_start = separator + 1
		if day_start == size {
			return Err(Incomplete)
		}
		day_first = byte_at(bytes, day_start)
		if day_first < 48 or day_first > 57 {
			return Err(Malformed)
		}
		if day_start + 1 == size {
			return if (day_first - 48) * 10 <= length {
				Err(Incomplete)
			} else {
				Err(InvalidDay)
			}
		}
		day_last = byte_at(bytes, day_start + 1)
		if day_last < 48 or day_last > 57 or day_start + 2 != size {
			return Err(Malformed)
		}
		from_fields({ year, month, day: (day_first - 48) * 10 + day_last - 48 })
	}

	## Total canonical output across this provider's full signed-year range.
	to_text : GregorianDate -> Str
	to_text = |Date(fields)| {
		year = if fields.year < 0 {
			"-${pad_year((-fields.year).to_str())}"
		} else if fields.year > 9999 {
			"+${fields.year.to_str()}"
		} else {
			pad_year(fields.year.to_str())
		}
		"${year}-${pad_two(fields.month)}-${pad_two(fields.day)}"
	}

	## Validate a proleptic Gregorian date with astronomical year numbering.
	## Return OutOfRange outside the supported year range, InvalidMonth outside
	## 1..12, or InvalidDay for a nonexistent day. No clamping is performed.
	from_fields : Fields -> Try(GregorianDate, [OutOfRange, InvalidMonth, InvalidDay, ..])
	from_fields = |fields| {
		length = days_in_month(fields.year, fields.month)?
		if fields.day < 1 or fields.day > length {
			return Err(InvalidDay)
		}
		Ok(Date(fields))
	}

	## Return the number of days in a Gregorian month, including its leap-year rule.
	## Reject unsupported years with OutOfRange and months outside 1..12 with InvalidMonth.
	days_in_month : I64, U8 -> Try(U8, [OutOfRange, InvalidMonth, ..])
	days_in_month = |year, month| {
		if year < -2147483648 or year > 2147483647 {
			return Err(OutOfRange)
		}
		if month < 1 or month > 12 {
			return Err(InvalidMonth)
		}
		Ok(month_length(year, month))
	}

	## Read the validated astronomical year and one-based month/day in the Gregorian calendar.
	to_fields : GregorianDate -> Fields
	to_fields = |Date(fields)| fields

	## Gregorian weekday, with the same seven tags as CalendarPattern.Weekday.
	## This queries the supplied civil date without selecting a timezone.
	weekday : GregorianDate -> Weekday
	weekday = |date| weekday_tag(weekday_index(CivilDay.to_day_number(to_civil_day(date))))

	## One-based day within the Gregorian year: 1..365, or 1..366 in leap years.
	## Total across the full supported year range, with constant bounded work.
	ordinal_day : GregorianDate -> U16
	ordinal_day = |date| {
		Date(fields) = date
		match I64.to_u16_try(CivilDay.to_day_number(to_civil_day(date)) - year_start(fields.year) + 1) {
			Ok(value) => value
			Err(_) => crash "Gregorian ordinal day invariant"
		}
	}

	## ISO weeks start Monday; week 1 contains January 4. The week-numbering
	## year can differ from the calendar year. Its I64 result can extend beyond
	## this date provider: 2147483647-12-30 belongs to 2147483648-W01.
	## Total, constant bounded scalar work; no adjacent date is constructed.
	iso_week_date : GregorianDate -> IsoWeekDate
	iso_week_date = |date| {
		Date(fields) = date
		number = CivilDay.to_day_number(to_civil_day(date))
		index = weekday_index(number)
		# Each ISO week belongs to the Gregorian year of its Thursday.
		# Moving at most three days stays far inside I64 at provider limits.
		thursday = number + 3 - index
		week_year = if thursday < year_start(fields.year) {
			fields.year - 1
		} else if thursday >= year_start(fields.year + 1) {
			fields.year + 1
		} else {
			fields.year
		}
		week = match I64.to_u8_try((thursday - year_start(week_year)) // 7 + 1) {
			Ok(value) => value # Thursday's zero-based year day is 0..365: weeks 1..53.
			Err(_) => crash "Gregorian ISO week invariant"
		}
		{ week_year, week, weekday: weekday_tag(index) }
	}

	## Convert this date to the shared civil-day coordinate.
	## Equal dates across calendars have equal coordinates; no timezone is chosen.
	to_civil_day : GregorianDate -> CivilDay
	to_civil_day = |Date(date)| {
		# Common-year days preceding each month. Nominal construction establishes
		# month 1..12; only dates after February need a leap-day correction.
		before = match date.month {
			1 => 0.I64
			2 => 31
			3 => 59
			4 => 90
			5 => 120
			6 => 151
			7 => 181
			8 => 212
			9 => 243
			10 => 273
			11 => 304
			_ => 334
		}
		leap_day = if date.month > 2 and month_length(date.year, 2) == 29 {
			1.I64
		} else {
			0.I64
		}
		CivilDay.from_day_number(year_start(date.year) + before + leap_day + U8.to_i64(date.day) - 1)
	}

	## Describe a shared civil-day coordinate in the Gregorian calendar.
	## Return OutOfRange if that day lies outside the supported year range.
	from_civil_day : CivilDay -> Try(GregorianDate, [OutOfRange, ..])
	from_civil_day = |day| {
		number = CivilDay.to_day_number(day)
		if number < first_supported_day or number >= after_last_supported_day {
			return Err(OutOfRange)
		}
		# March-based Gregorian eras, adapted from Howard Hinnant's
		# civil_from_days (2021-09-01), donated to the public domain:
		# https://howardhinnant.github.io/date_algorithms.html#civil_from_days
		# Validate before shifting: arbitrary CivilDay inputs may be I64 extremes.
		# The provider range keeps every intermediate within I64.
		shifted = number + 719468
		era = I64.div_floor_by(shifted, 146097)
		# Floor division leaves a nonnegative era remainder, even for negative
		# years. Only this bounded remainder is narrowed: era/year stay I64.
		era_day = match I64.to_u32_try(shifted - era * 146097) {
			Ok(value) => value # 0..146096
			Err(_) => crash "Gregorian era remainder invariant"
		}
		# era_year is 0..399; year_day is 0..365; march_month is 0..11.
		# All unsigned subtractions are nonnegative in this decomposition.
		# Its largest intermediate is below 2^18, safely inside U32.
		era_year = (era_day - era_day // 1460 + era_day // 36524 - era_day // 146096) // 365
		year_day = era_day - (365 * era_year + era_year // 4 - era_year // 100)
		march_month = (5 * year_day + 2) // 153
		month_number = if march_month < 10 {
			march_month + 3
		} else {
			march_month - 9
		}
		day_number = year_day - (153 * march_month + 2) // 5 + 1
		year = era * 400 + era_year.to_i64() + if month_number <= 2 {
			1
		} else {
			0
		}
		# The decomposition guarantees month 1..12 and day 1..31.
		month = match U32.to_u8_try(month_number) {
			Ok(value) => value
			Err(_) => crash "Gregorian month decomposition invariant"
		}
		day_of_month = match U32.to_u8_try(day_number) {
			Ok(value) => value
			Err(_) => crash "Gregorian day decomposition invariant"
		}
		Ok(Date({ year, month, day: day_of_month }))
	}

	## Hash Gregorian dates consistently with equality for dictionary and set keys.
	## Hash values are not a stable serialization format.
	to_hash : GregorianDate, Hasher -> Hasher
	to_hash = |Date(fields), hasher| fields.day.to_hash(fields.month.to_hash(fields.year.to_hash(hasher)))

	## Return a concise diagnostic description of these Gregorian dates.
	## Use explicit conversions or text serialization when storing or exchanging data.
	to_inspect : GregorianDate -> Str
	to_inspect = |Date(fields)| "GregorianDate(${fields.year.to_str()}, ${fields.month.to_str()}, ${fields.day.to_str()})"

	## Whether the first of two Gregorian dates precedes the second in their numeric order.
	is_lt : GregorianDate, GregorianDate -> Bool
	is_lt = |a, b| to_civil_day(a) < to_civil_day(b)

	## Whether the first of two Gregorian dates precedes or equals the second.
	is_lte : GregorianDate, GregorianDate -> Bool
	is_lte = |a, b| to_civil_day(a) <= to_civil_day(b)

	## Whether the first of two Gregorian dates follows the second in their numeric order.
	is_gt : GregorianDate, GregorianDate -> Bool
	is_gt = |a, b| to_civil_day(a) > to_civil_day(b)

	## Whether the first of two Gregorian dates follows or equals the second.
	is_gte : GregorianDate, GregorianDate -> Bool
	is_gte = |a, b| to_civil_day(a) >= to_civil_day(b)

	## Equality of Gregorian dates; values of other temporal domains must be converted explicitly.
	is_eq : GregorianDate, GregorianDate -> Bool
	is_eq = |Date(a), Date(b)| a.year == b.year and a.month == b.month and a.day == b.day

	expect from_civil_day(CivilDay.from_day_number(I64.lowest)) == Err(OutOfRange)
	# R05: calendar-year and ISO-year transitions, including signed provider
	# endpoints. Extended-year expectations use Gregorian 400-year periodicity;
	# these are not a claim that Python datetime supports signed years.
	expect {
		var $valid = Bool.True
		for fixture in [
			{ text: "1970-01-01", ordinal: 1.U16, iso: { week_year: 1970.I64, week: 1.U8, weekday: Thursday } },
			{ text: "2020-12-31", ordinal: 366, iso: { week_year: 2020, week: 53, weekday: Thursday } },
			{ text: "2021-01-01", ordinal: 1, iso: { week_year: 2020, week: 53, weekday: Friday } },
			{ text: "2021-01-04", ordinal: 4, iso: { week_year: 2021, week: 1, weekday: Monday } },
			{ text: "1900-03-01", ordinal: 60, iso: { week_year: 1900, week: 9, weekday: Thursday } },
			{ text: "2000-03-01", ordinal: 61, iso: { week_year: 2000, week: 9, weekday: Wednesday } },
			{ text: "0000-01-01", ordinal: 1, iso: { week_year: -1, week: 52, weekday: Saturday } },
			{ text: "-2147483648-01-01", ordinal: 1, iso: { week_year: -2147483648, week: 1, weekday: Tuesday } },
			{ text: "+2147483647-12-30", ordinal: 364, iso: { week_year: 2147483648, week: 1, weekday: Monday } },
			{ text: "+2147483647-12-31", ordinal: 365, iso: { week_year: 2147483648, week: 1, weekday: Tuesday } },
		] {
			$valid = $valid and match parse(fixture.text) {
				Ok(date) => ordinal_day(date) == fixture.ordinal and weekday(date) == fixture.iso.weekday and iso_week_date(date) == fixture.iso
				Err(_) => Bool.False
			}
		}
		$valid
	}
	# RFC 3339 (July 2002), sections 5.6-5.8: full-date grammar and
	# Gregorian month/leap-day restrictions. Signed fixtures are explicitly
	# native-profile extensions, not RFC examples.
	# https://www.rfc-editor.org/rfc/rfc3339.html#section-5.6
	expect {
		var $valid = Bool.True
		for fixture in [
			{ text: "1985-04-12", fields: { year: 1985.I64, month: 4.U8, day: 12.U8 } },
			{ text: "2000-02-29", fields: { year: 2000, month: 2, day: 29 } },
			{ text: "0000-02-29", fields: { year: 0, month: 2, day: 29 } },
			{ text: "-0001-12-31", fields: { year: -1, month: 12, day: 31 } },
			{ text: "+10000-01-01", fields: { year: 10000, month: 1, day: 1 } },
			{ text: "-2147483648-01-01", fields: { year: -2147483648, month: 1, day: 1 } },
			{ text: "+2147483647-12-31", fields: { year: 2147483647, month: 12, day: 31 } },
		] {
			$valid = $valid and parse(fixture.text) == from_fields(fixture.fields)
			$valid = $valid and match from_fields(fixture.fields) {
				Ok(value) => to_text(value) == fixture.text
				Err(_) => Bool.False
			}
		}
		$valid
	}
	expect parse("1900-02-29") == Err(InvalidDay)
	expect parse("1900-02-2") == Err(Incomplete)
	expect parse("1900-02-3") == Err(InvalidDay)
	expect parse("2026-13-") == Err(InvalidMonth)
	expect parse("2026") == Err(Incomplete)
	expect parse("-0000-01-01") == Err(Malformed)
	expect parse("+2026-01-01") == Err(Malformed)
	expect parse("-00001-01-01") == Err(Malformed)
	expect parse("+2147483648-01-01") == Err(OutOfRange)
	expect parse("-2147483649-01-01") == Err(OutOfRange)
	expect parse("2026-01-01Z") == Err(Malformed)
	expect parse("é".repeat(33)) == Err(TooLarge)
	expect from_civil_day(CivilDay.from_day_number(I64.highest)) == Err(OutOfRange)
	expect from_fields({ year: 1900, month: 2, day: 29 }) == Err(InvalidDay)
	expect from_fields({ year: 2000, month: 0, day: 1 }) == Err(InvalidMonth)
	expect from_fields({ year: 2147483648, month: 1, day: 1 }) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(-784353015834)) == Err(OutOfRange)
	expect from_civil_day(CivilDay.from_day_number(784351576777)) == Err(OutOfRange)
	expect {
		var $valid = Bool.True
		for fixture in [
			{ fields: { year: 1970.I64, month: 1.U8, day: 1.U8 }, number: 0.I64 },
			{ fields: { year: 1, month: 1, day: 1 }, number: -719162 },
			{ fields: { year: 0, month: 1, day: 1 }, number: -719528 },
			{ fields: { year: 0, month: 2, day: 29 }, number: -719469 },
			{ fields: { year: -2147483648, month: 1, day: 1 }, number: -784353015833 },
			{ fields: { year: 2147483647, month: 12, day: 31 }, number: 784351576776 },
		] {
			date = from_fields(fixture.fields)
			coordinate = CivilDay.from_day_number(fixture.number)
			$valid = $valid and from_civil_day(coordinate) == date
			$valid = $valid and match date {
				Ok(value) => CivilDay.is_eq(to_civil_day(value), coordinate)
				Err(_) => Bool.False
			}
		}
		$valid
	}
}

# Civil dates restrict day numbers to the provider range, so adding 3 fits I64.
weekday_index : I64 -> I64
weekday_index = |day| I64.mod_by(day + 3, 7)

# The civil weekday remainder is 0..6, Monday through Sunday.
weekday_tag : I64 -> GregorianDate.Weekday
weekday_tag = |index| match index {
	0 => Monday
	1 => Tuesday
	2 => Wednesday
	3 => Thursday
	4 => Friday
	5 => Saturday
	_ => Sunday
}

# Every caller checks the bounded input index before access.
byte_at = |bytes, index| match List.get(bytes, index) {
	Ok(value) => value
	Err(_) => crash "Gregorian text index invariant"
}

pad_year = |text| if text.count_utf8_bytes() < 4 {
	"${"0".repeat(4 - text.count_utf8_bytes())}${text}"
} else {
	text
}

pad_two = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}

# Provider bounds are immutable and evaluated once at compile time. Every
# inverse conversion validates against them without recomputing either year.
first_supported_day : I64
first_supported_day = year_start(-2147483648)
after_last_supported_day : I64
after_last_supported_day = year_start(2147483648)

# Counts complete years before January 1 relative to Gregorian 1970-01-01.
# All callers constrain year to [-2147483648, 2147483648]; intermediates fit I64.
# Floor division, including before year zero, counts Gregorian leap years.
year_start : I64 -> I64
year_start = |year| {
	previous = year - 1
	365 * previous + I64.div_floor_by(previous, 4) - I64.div_floor_by(previous, 100) + I64.div_floor_by(previous, 400) - 719162
}

# Internal callers establish a valid year and month in 1..12.
month_length : I64, U8 -> U8
month_length = |year, month| {
	match month {
		2 => if I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0) {
			29
		} else {
			28
		}
		4 | 6 | 9 | 11 => 30
		_ => 31
	}
}

## R05: enumerate a complete Gregorian cycle independently of year-counting.
expect {
	var $valid = Bool.True
	var $number = -719528.I64
	var $year = 0.I64
	while $year < 400 {
		var $month = 1.U8
		for common_length in [31.U8, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] {
			leap = I64.rem_by($year, 4) == 0 and (I64.rem_by($year, 100) != 0 or I64.rem_by($year, 400) == 0)
			length = if $month == 2 and leap {
				29.U8
			} else {
				common_length
			}
			var $day = 1.U8
			while $day <= length {
				# Translate the enumerated cycle across year zero and near both
				# provider extremes using the independently counted cycle length.
				for offset in [-2147483600.I64, -400, 0, 2147483200] {
					fields = { year: $year + offset, month: $month, day: $day }
					coordinate = CivilDay.from_day_number(
						$number + I64.div_trunc_by(offset, 400) * 146097,
					)
					date = GregorianDate.from_fields(fields)
					$valid = $valid and GregorianDate.from_civil_day(coordinate) == date
					$valid = $valid and match date {
						Ok(value) => CivilDay.is_eq(GregorianDate.to_civil_day(value), coordinate)
						Err(_) => Bool.False
					}
				}
				$number = $number + 1
				$day = $day + 1
			}
			$month = $month + 1
		}
		$year = $year + 1
	}
	$valid and $number == -573431
}
