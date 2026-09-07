import fuzz.Fuzz
import time.CivilDay
import time.GregorianDate
import time.EnglishGregorian

# R05: full provider day domain plus invalid day numbers and malformed fields.
GregorianCase := { number : I64, raw : U64, month : U8, day : U8 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(GregorianCase)
	generator_for = |_| {
		number: Fuzz.map2(
			Fuzz.u8_in(0, 5),
			Fuzz.u64_in(0, 1568704592609),
			|selector, n| {
				match selector {
					0 => -784353015833.I64
					1 => 784351576776.I64
					2 => -719469.I64
					_ => U64.to_i64_wrap(n) - 784353015833
				}
			},
		),
		raw: Fuzz.u64,
		month: Fuzz.u8,
		day: Fuzz.u8,
	}.Fuzz

	check : GregorianCase -> Fuzz.Outcome
	check = |input| {
		coordinate = CivilDay.from_day_number(input.number)
		date = match GregorianDate.from_civil_day(coordinate) {
			Ok(value) => value
			Err(_) => crash "R05 provider rejected valid day number"
		}
		if !CivilDay.is_eq(GregorianDate.to_civil_day(date), coordinate) {
			crash "R05 civil coordinate round trip"
		}
		fields = GregorianDate.to_fields(date)
		# R14: independently assemble the declared native grammar from fields.
		# This does not use production formatting as the parser's oracle.
		magnitude = if fields.year < 0 {
			-fields.year
		} else {
			fields.year
		}
		raw_year = magnitude.to_str()
		year_digits = if magnitude < 10 {
			"000${raw_year}"
		} else if magnitude < 100 {
			"00${raw_year}"
		} else if magnitude < 1000 {
			"0${raw_year}"
		} else {
			raw_year
		}
		year_text = if fields.year < 0 {
			"-${year_digits}"
		} else if fields.year > 9999 {
			"+${year_digits}"
		} else {
			year_digits
		}
		month_text = if fields.month < 10 {
			"0${fields.month.to_str()}"
		} else {
			fields.month.to_str()
		}
		day_text = if fields.day < 10 {
			"0${fields.day.to_str()}"
		} else {
			fields.day.to_str()
		}
		expected_text = "${year_text}-${month_text}-${day_text}"
		if GregorianDate.parse(expected_text) != Ok(date) or GregorianDate.to_text(date) != expected_text {
			crash "R14 full-range Gregorian native text differs from field model"
		}
		# R14/R16: English month spellings independently checked against RFC9110
		# (June 2022), section 5.6.7. Only month names are shared with HTTP dates;
		# unpadded day and signed year output follow our native display profile.
		# https://www.rfc-editor.org/rfc/rfc9110.html#section-5.6.7
		month_name = match ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].get(fields.month.to_u64() - 1) {
			Ok(name) => name
			Err(_) => crash "validated month outside oracle table"
		}
		expected_display = "${fields.day.to_str()} ${month_name} ${year_text}"
		if EnglishGregorian.date(date) != expected_display {
			crash "English Gregorian date differs from independent field text"
		}
		# Independent month walk checks every boundary at the generated full-range
		# year. January's coordinate anchors the year; summing month lengths does
		# not share the production prefix table or inverse decomposition.
		january = match GregorianDate.from_fields({ year: fields.year, month: 1, day: 1 }) {
			Ok(value) => value
			Err(_) => crash "valid model year"
		}
		var $expected = CivilDay.to_day_number(GregorianDate.to_civil_day(january))
		for month in [1.U8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
			length = days_in_month(fields.year, month)
			for day in [1.U8, length] {
				boundary = match GregorianDate.from_fields({ year: fields.year, month, day }) {
					Ok(value) => value
					Err(_) => crash "valid model month boundary"
				}
				if CivilDay.to_day_number(GregorianDate.to_civil_day(boundary)) != $expected + day.to_i64() - 1 {
					crash "R05 month prefix differs from independent month walk"
				}
			}
			$expected = $expected + length.to_i64()
		}
		if GregorianDate.from_fields(fields) != Ok(date) {
			crash "R05 validated field round trip"
		}
		# Independent next-day model: advance fields by calendar month lengths,
		# rather than using the production year-count formula or inverse decomposition.
		if input.number < 784351576776 {
			length = days_in_month(fields.year, fields.month)
			next = if fields.day < length {
				{ year: fields.year, month: fields.month, day: fields.day + 1 }
			} else if fields.month < 12 {
				{ year: fields.year, month: fields.month + 1, day: 1.U8 }
			} else {
				{ year: fields.year + 1, month: 1.U8, day: 1.U8 }
			}
			if GregorianDate.from_fields(next) != GregorianDate.from_civil_day(CivilDay.from_day_number(input.number + 1)) {
				crash "R05 conversion disagrees with next-day model"
			}
		}
		# No constructor preconditions are discarded: assert exact rejection class.
		year = U64.to_i64_wrap(input.raw)
		constructed = GregorianDate.from_fields({ year, month: input.month, day: input.day })
		if year < -2147483648 or year > 2147483647 {
			if constructed != Err(OutOfRange) {
				crash "R05 invalid year accepted"
			}
		} else if input.month < 1 or input.month > 12 {
			if constructed != Err(InvalidMonth) {
				crash "R05 invalid month accepted"
			}
		} else if input.day < 1 or input.day > days_in_month(year, input.month) {
			if constructed != Err(InvalidDay) {
				crash "R05 invalid day accepted"
			}
		} else {
			match constructed {
				Ok(_) => {}
				Err(_) => crash "R05 valid fields rejected"
			}
		}
		outside = CivilDay.from_day_number(year)
		if year < -784353015833 or year > 784351576776 {
			if GregorianDate.from_civil_day(outside) != Err(OutOfRange) {
				crash "R05 out-of-provider day accepted"
			}
		}
		Fuzz.keep
	}
}

days_in_month = |year, month| {
	lengths = [31.U8, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	base = match List.get(lengths, U8.to_u64(month - 1)) {
		Ok(value) => value
		Err(_) => crash "test model month precondition"
	}
	if month == 2 and I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0) {
		base + 1
	} else {
		base
	}
}
