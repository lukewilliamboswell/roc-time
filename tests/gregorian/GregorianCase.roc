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
		# R05/R16: full-range queries agree with a bounded cycle/month walk.
		# 2000-01-01 was Saturday. A Gregorian 400-year cycle has 146097
		# days (a multiple of seven); no production day-number formula is used.
		cycle_year = 2000 + I64.mod_by(fields.year, 400)
		var $january_weekday = 6.I64
		var $model_year = 2000.I64
		while $model_year < cycle_year {
			$january_weekday = I64.mod_by($january_weekday - 1 + year_length($model_year), 7) + 1
			$model_year = $model_year + 1
		}
		var $ordinal = fields.day.to_i64()
		var $month = 1.U8
		while $month < fields.month {
			$ordinal = $ordinal + days_in_month(fields.year, $month).to_i64()
			$month = $month + 1
		}
		expected_weekday = I64.mod_by($january_weekday + $ordinal - 2, 7) + 1
		var $thursday = $ordinal + 4 - expected_weekday
		var $week_year = fields.year
		if $thursday < 1 {
			$week_year = $week_year - 1
			$thursday = $thursday + year_length($week_year)
		} else if $thursday > year_length(fields.year) {
			$thursday = $thursday - year_length(fields.year)
			$week_year = $week_year + 1
		}
		week = GregorianDate.iso_week_date(date)
		if GregorianDate.ordinal_day(date).to_i64() != $ordinal or
			weekday_number(GregorianDate.weekday(date)) != expected_weekday or
				weekday_number(week.weekday) != expected_weekday or
					week.week_year != $week_year or week.week.to_i64() != I64.div_trunc_by($thursday - 1, 7) + 1 {
			crash "R05 civil queries differ from cycle/month walk"
		}
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
			next_date = match GregorianDate.from_fields(next) {
				Ok(value) => value
				Err(_) => crash "valid successor"
			}
			if weekday_number(GregorianDate.weekday(next_date)) != I64.mod_by(expected_weekday, 7) + 1 {
				crash "R05 weekday successor"
			}
		}
		# No constructor preconditions are discarded: assert exact rejection class.
		# Deliberately exercise malformed month/day paths within a valid year;
		# uniform I64 years almost always stop at OutOfRange first.
		year = if U64.rem_by(input.raw, 2) == 0 {
			fields.year
		} else {
			U64.to_i64_wrap(input.raw)
		}
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

weekday_number : GregorianDate.Weekday -> I64
weekday_number = |day| match day {
	Monday => 1
	Tuesday => 2
	Wednesday => 3
	Thursday => 4
	Friday => 5
	Saturday => 6
	Sunday => 7
}

year_length = |year| if days_in_month(year, 2) == 29 {
	366.I64
} else {
	365.I64
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
