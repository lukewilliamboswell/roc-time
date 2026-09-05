import time.CivilDay
import time.GregorianDate

## Inputs only: expected observations are kept outside the Roc process.
GregorianOracle := [Forward(U64, I64, U8, U8), Inverse(U64, I64)].{
	observe : GregorianOracle -> Str
	observe = |input| {
		match input {
			Forward(id, year, month, day) => {
				prefix = id.to_str()
				match GregorianDate.from_fields({ year, month, day }) {
					Ok(date) => "${prefix}|ok|${CivilDay.to_day_number(GregorianDate.to_civil_day(date)).to_str()}"
					Err(OutOfRange) => "${prefix}|error|OutOfRange"
					Err(InvalidMonth) => "${prefix}|error|InvalidMonth"
					Err(InvalidDay) => "${prefix}|error|InvalidDay"
				}
			}
			Inverse(id, number) => {
				prefix = id.to_str()
				match GregorianDate.from_civil_day(CivilDay.from_day_number(number)) {
					Ok(date) => {
						f = GregorianDate.to_fields(date)
						"${prefix}|ok|${f.year.to_str()}|${f.month.to_str()}|${f.day.to_str()}"
					}
					Err(OutOfRange) => "${prefix}|error|OutOfRange"
				}
			}
		}
	}
}
