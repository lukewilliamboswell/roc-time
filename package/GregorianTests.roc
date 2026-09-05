import CivilDay
import GregorianDate

## R05: enumerate a complete Gregorian cycle independently of year-counting.
GregorianTests :: [].{
	expect {
		var valid = Bool.True
		var number = -719528.I64
		var year = 0.I64
		while year < 400 {
			var month = 1.U8
			for common_length in [31.U8, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] {
				leap = I64.rem_by(year, 4) == 0 and (I64.rem_by(year, 100) != 0 or I64.rem_by(year, 400) == 0)
				length = if month == 2 and leap {
					29.U8
				} else {
					common_length
				}
				var day = 1.U8
				while day <= length {
					# Translate each enumerated day to the previous cycle as well;
					# this crosses year zero without using a floor-division oracle.
					for offset in [-400.I64, 0] {
						fields = { year: year + offset, month, day }
						coordinate = CivilDay.from_day_number(
							number + if offset == 0 {
								0
							} else {
								-146097
							},
						)
						date = GregorianDate.from_fields(fields)
						valid = valid and GregorianDate.from_civil_day(coordinate) == date
						valid = valid and match date {
							Ok(value) => CivilDay.is_eq(GregorianDate.to_civil_day(value), coordinate)
							Err(_) => Bool.False
						}
					}
					number = number + 1
					day = day + 1
				}
				month = month + 1
			}
			year = year + 1
		}
		valid and number == -573431
	}
}
