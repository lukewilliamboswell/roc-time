import time.GregorianDate

QueryFixture := [].{
	make = |count| {
		var $dates = []
		var $i = 0.U64
		while $i < count {
			fields = match U64.rem_by($i, 6) {
				0 => { year: 2020.I64, month: 12.U8, day: 31.U8 }
				1 => { year: 2021, month: 1, day: 1 }
				2 => { year: 2021, month: 1, day: 4 }
				3 => { year: 0, month: 1, day: 1 }
				4 => { year: 2147483647, month: 12, day: 30 }
				_ => { year: -2147483648, month: 1, day: 1 }
			}
			date = match GregorianDate.from_fields(fields) {
				Ok(value) => value
				Err(_) => crash "valid resource fixture"
			}
			$dates = $dates.append(date)
			$i = $i + 1
		}
		$dates
	}

	expected = |year, _month, day| {
		match year {
			2020 => { ordinal: 366.U16, weekday: Thursday, year: 2020.I64, week: 53.U8 }
			2021 => if day == 1 {
				{ ordinal: 1, weekday: Friday, year: 2020, week: 53 }
			} else {
				{ ordinal: 4, weekday: Monday, year: 2021, week: 1 }
			}
			0 => { ordinal: 1, weekday: Saturday, year: -1, week: 52 }
			2147483647 => { ordinal: 364, weekday: Monday, year: 2147483648, week: 1 }
			_ => { ordinal: 1, weekday: Tuesday, year: -2147483648, week: 1 }
		}
	}
}
