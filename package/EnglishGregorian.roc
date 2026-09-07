import Calendar
import GregorianDate
import ClockTime
import LocalDateTime

## Small English Gregorian display profile, english-gregorian-short-v1.
## Dates use an unpadded day and English three-letter month: 7 Sep 2026.
## Years use astronomical numbering (0000 is 1 BCE), with the same sign and
## padding as GregorianDate.to_text across its full supported year range.
## This display text is not a persistence format or a parseable-text contract.
##
## The caller selects clock precision. Minute and Second reject any nonzero
## omitted fields; Exact includes seconds and the shortest exact fraction.
## No rounding or truncation occurs. Clock labels do not retain supplied-field
## resolution, so Exact preserves the value rather than its original spelling.
## Description types remain separate from these full-date and boundary labels.
##
## Local labels need no zone to display. Display does not prove a label exists
## in a zone or select an occurrence. Project resolved values using an explicitly
## chosen context first. Non-Gregorian local values return UnsupportedCalendar;
## explicit calendar conversion is a separate operation.
##
## Work and output are bounded by the scalar fields: at most 18 ASCII bytes for
## a date, 15 for a clock, and 35 for a local date/time. No provider lookup,
## recurrence, ambient locale or clock access occurs. These bounds do not claim
## an allocation count or native layout.
##
## ```roc
## import time.EnglishGregorian
## import time.GregorianDate
## import time.LocalDateTime
##
## expect {
##     due = GregorianDate.parse("2026-09-07")?
##     appointment = LocalDateTime.parse_gregorian("2026-09-07T09:30")?
##     EnglishGregorian.date(due) == "7 Sep 2026" and
##         EnglishGregorian.local_datetime(appointment, Minute) == Ok("7 Sep 2026, 09:30")
## }
## ```
##
## Examples assume a package dependency named `time`.
EnglishGregorian :: [].{
	Precision : [Minute, Second, Exact]
	PrecisionError : [PrecisionLoss(Precision)]
	Error : [UnsupportedCalendar(Calendar), PrecisionLoss(Precision)]

	profile : Str
	profile = "english-gregorian-short-v1"

	date : GregorianDate -> Str
	date = |value| {
		fields = GregorianDate.to_fields(value)
		"${fields.day.to_str()} ${month_name(fields.month)} ${year_text(fields.year)}"
	}

	clock : ClockTime, Precision -> Try(Str, PrecisionError)
	clock = |value, precision| {
		fields = ClockTime.to_fields(value)
		match precision {
			Minute => {
				if fields.second != 0 or fields.microsecond != 0 {
					return Err(PrecisionLoss(Minute))
				}
				Ok("${two_digits(fields.hour)}:${two_digits(fields.minute)}")
			}
			Second => {
				if fields.microsecond != 0 {
					return Err(PrecisionLoss(Second))
				}
				Ok(ClockTime.to_text(value))
			}
			Exact => Ok(ClockTime.to_text(value))
		}
	}

	## Calendar access is checked before clock precision. The source label is
	## never converted, resolved or rounded as part of presentation.
	local_datetime : LocalDateTime, Precision -> Try(Str, Error)
	local_datetime = |value, precision| {
		day = Calendar.Date.as_gregorian(LocalDateTime.date(value))?
		time = match clock(LocalDateTime.clock(value), precision) {
			Ok(rendered) => rendered
			Err(PrecisionLoss(requested)) => return Err(PrecisionLoss(requested))
		}
		Ok("${date(day)}, ${time}")
	}

	expect {
		# English month spellings are independently specified by RFC 9110
		# (June 2022), section 5.6.7:
		# https://www.rfc-editor.org/rfc/rfc9110.html#section-5.6.7
		# This finite intersection does not make the display an HTTP-date.
		fixtures = [
			{ month: 1.U8, expected: "7 Jan 2026" },
			{ month: 2, expected: "7 Feb 2026" },
			{ month: 3, expected: "7 Mar 2026" },
			{ month: 4, expected: "7 Apr 2026" },
			{ month: 5, expected: "7 May 2026" },
			{ month: 6, expected: "7 Jun 2026" },
			{ month: 7, expected: "7 Jul 2026" },
			{ month: 8, expected: "7 Aug 2026" },
			{ month: 9, expected: "7 Sep 2026" },
			{ month: 10, expected: "7 Oct 2026" },
			{ month: 11, expected: "7 Nov 2026" },
			{ month: 12, expected: "7 Dec 2026" },
		]
		var $valid = Bool.True
		for fixture in fixtures {
			value = GregorianDate.from_fields({ year: 2026, month: fixture.month, day: 7 })?
			$valid = $valid and date(value) == fixture.expected
		}
		$valid
	}

	expect {
		fixtures = [
			{ year: -2147483648.I64, expected: "1 Jan -2147483648" },
			{ year: -10000, expected: "1 Jan -10000" },
			{ year: -1, expected: "1 Jan -0001" },
			{ year: 0, expected: "1 Jan 0000" },
			{ year: 1, expected: "1 Jan 0001" },
			{ year: 9999, expected: "1 Jan 9999" },
			{ year: 10000, expected: "1 Jan +10000" },
			{ year: 2147483647, expected: "1 Jan +2147483647" },
		]
		var $valid = Bool.True
		for fixture in fixtures {
			value = GregorianDate.from_fields({ year: fixture.year, month: 1, day: 1 })?
			$valid = $valid and date(value) == fixture.expected
		}
		$valid and date(GregorianDate.from_fields({ year: 2147483647, month: 12, day: 31 })?) == "31 Dec +2147483647"
	}

	expect {
		minute = ClockTime.parse("09:30")?
		second = ClockTime.parse("09:30:01")?
		fraction = ClockTime.parse("09:30:00.000001")?
		clock(minute, Minute) == Ok("09:30") and
			clock(minute, Second) == Ok("09:30:00") and
				clock(minute, Exact) == Ok("09:30:00") and
					clock(second, Minute) == Err(PrecisionLoss(Minute)) and
						clock(second, Second) == Ok("09:30:01") and
							clock(fraction, Minute) == Err(PrecisionLoss(Minute)) and
								clock(fraction, Second) == Err(PrecisionLoss(Second)) and
									clock(fraction, Exact) == Ok("09:30:00.000001")
	}

	expect {
		clock(ClockTime.parse("00:00")?, Minute) == Ok("00:00") and
			clock(ClockTime.parse("23:59:59.999999")?, Exact) == Ok("23:59:59.999999") and
				clock(ClockTime.parse("12:30:00.120")?, Exact) == Ok("12:30:00.12")
	}

	expect {
		appointment = LocalDateTime.parse_gregorian("2026-09-07T09:30")?
		local_datetime(appointment, Minute) == Ok("7 Sep 2026, 09:30") and
			local_datetime(appointment, Second) == Ok("7 Sep 2026, 09:30:00") and
				local_datetime(LocalDateTime.parse_gregorian("2026-09-07T09:30:00.1")?, Minute) == Err(PrecisionLoss(Minute))
	}

	expect {
		julian = Calendar.Date.from_fields(Julian, { year: 2026, month: 9, day: 7 })?
		value = LocalDateTime.new(julian, ClockTime.parse("09:30:00.000001")?)
		local_datetime(value, Exact) == Err(UnsupportedCalendar(Julian)) and
			local_datetime(value, Minute) == Err(UnsupportedCalendar(Julian))
	}

	expect {
		first = LocalDateTime.parse_gregorian("-2147483648-01-01T00:00")?
		last = LocalDateTime.parse_gregorian("+2147483647-12-31T23:59:59.999999")?
		local_datetime(first, Minute) == Ok("1 Jan -2147483648, 00:00") and
			local_datetime(last, Exact) == Ok("31 Dec +2147483647, 23:59:59.999999")
	}
}

month_name = |month| match month {
	1 => "Jan"
	2 => "Feb"
	3 => "Mar"
	4 => "Apr"
	5 => "May"
	6 => "Jun"
	7 => "Jul"
	8 => "Aug"
	9 => "Sep"
	10 => "Oct"
	11 => "Nov"
	12 => "Dec"
	_ => crash "GregorianDate month invariant"
}

year_text = |year| {
	# GregorianDate has validated the I32-sized provider range. Negation of a
	# negative year therefore fits I64, including the lowest provider year.
	if year < 0 {
		"-${four_digits((-year).to_str())}"
	} else if year > 9999 {
		"+${year.to_str()}"
	} else {
		four_digits(year.to_str())
	}
}

four_digits = |text| {
	var $result = text
	while $result.count_utf8_bytes() < 4 {
		$result = "0${$result}"
	}
	$result
}

two_digits = |value| if value < 10 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
