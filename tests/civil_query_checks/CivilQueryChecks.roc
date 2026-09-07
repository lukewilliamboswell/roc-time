import time.GregorianDate

## R02/R05/R16: independent seven-day walk; see provenance.md.
CivilQueryChecks :: [].{
	query = |text| {
		date = GregorianDate.parse(text)?
		iso = GregorianDate.iso_week_date(date)
		Ok("${number(GregorianDate.weekday(date)).to_str()},${GregorianDate.ordinal_day(date).to_str()},${iso.week_year.to_str()},${iso.week.to_str()},${number(iso.weekday).to_str()}")
	}

	cycle = |control| {
		var $weekday = 6.U8
		var $week = 52.U8
		var $week_year = 1999.I64
		var $year = 2000.I64
		var $count = 0.U64
		while $year < 2400 {
			var $ordinal = 1.U16
			var $month = 1.U8
			while $month <= 12 {
				length = match $month {
					2 => if I64.rem_by($year, 4) == 0 and (I64.rem_by($year, 100) != 0 or I64.rem_by($year, 400) == 0) {
						29.U8
					} else {
						28.U8
					}
					4 | 6 | 9 | 11 => 30.U8
					_ => 31.U8
				}
				var $day = 1.U8
				while $day <= length {
					if $weekday == 1 {
						if $month == 12 and $day >= 29 {
							$week_year = $year + 1
							$week = 1
						} else if $month == 1 and $day <= 4 {
							$week_year = $year
							$week = 1
						} else {
							$week = $week + 1
						}
					}
					date = match GregorianDate.from_fields({ year: $year, month: $month, day: $day }) {
						Ok(value) => value
						Err(_) => crash "day walk constructed invalid Gregorian date"
					}
					iso = GregorianDate.iso_week_date(date)
					expected_week = if control == "wrong-week" {
						0.U8
					} else {
						$week
					}
					if number(GregorianDate.weekday(date)) != $weekday or GregorianDate.ordinal_day(date) != $ordinal or iso.week_year != $week_year or iso.week != expected_week or number(iso.weekday) != $weekday {
						crash "Gregorian query differs from independent day walk"
					}
					$count = $count + 1
					$weekday = if $weekday == 7 {
						1
					} else {
						$weekday + 1
					}
					$ordinal = $ordinal + 1
					$day = $day + 1
				}
				$month = $month + 1
			}
			$year = $year + 1
		}
		$count
	}
}

number : GregorianDate.Weekday -> U8
number = |weekday| match weekday {
	Monday => 1
	Tuesday => 2
	Wednesday => 3
	Thursday => 4
	Friday => 5
	Saturday => 6
	Sunday => 7
}
