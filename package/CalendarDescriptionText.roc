CalendarDescriptionText := [].{
	summary = |data| {
		name = match data.kind {
			CalendarValue => "Calendar.Value"
			QualifiedCalendarValue => "QualifiedCalendarValue"
			EdtfDate => "EdtfDate"
		}
		date = date_text(data.fields, data.resolution)
		time = match data.resolution {
			Year => ""
			Month => ""
			Day => ""
			Hour => "T${two(data.clock.hour)}"
			Minute => "T${two(data.clock.hour)}:${two(data.clock.minute)}"
			Second => "T${clock_text(data.clock, 0)}"
			Fraction(digits) => "T${clock_text(data.clock, digits)}"
		}
		"${name}(calendar=${data.calendar}, value=${date}${time}, resolution=${Str.inspect(data.resolution)}, qualifications=${data.qualification_count.to_str()})"

	}
}

date_text = |fields, resolution| {
	year = fields.year.to_str()
	match resolution {
		Year => year
		Month => "${year}-${two(fields.month)}"
		_ => "${year}-${two(fields.month)}-${two(fields.day)}"
	}
}

two : U8 -> Str
two = |number| if number < 10 {
	"0${number.to_str()}"
} else {
	number.to_str()
}

clock_text = |clock, digits| {
	base = "${two(clock.hour)}:${two(clock.minute)}:${two(clock.second)}"
	if digits > 6 {
		return "${base}[microsecond=${clock.microsecond.to_str()}, digits=${digits.to_str()}]"
	}
	var $divisor = 1.U32
	var $remaining = 6.U8 - digits
	while $remaining > 0 {
		$divisor = $divisor * 10
		$remaining = $remaining - 1
	}
	if U32.rem_by(clock.microsecond, $divisor) != 0 or clock.microsecond > 999999 {
		return "${base}[microsecond=${clock.microsecond.to_str()}, digits=${digits.to_str()}]"
	}
	if digits == 0 {
		return base
	}
	fraction = U32.div_trunc_by(clock.microsecond, $divisor).to_str()
	"${base}.${"0".repeat(digits.to_u64() - fraction.count_utf8_bytes())}${fraction}"
}
