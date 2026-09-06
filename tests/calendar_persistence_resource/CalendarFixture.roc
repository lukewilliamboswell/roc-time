import time.CalendarValue
import time.QualifiedCalendarValue
import time.CalendarDate

CalendarFixture := [].{
	value : I64, U8 -> CalendarValue
	value = |year, digits| {
		date = match CalendarDate.from_fields(Julian, { year, month: 12, day: 31 }) {
			Ok(value) => value
			Err(_) => crash "fixture calendar date"
		}
		var fraction = 1.U32
		var remaining = digits
		while remaining > 0 {
			fraction = fraction * 10
			remaining = remaining - 1
		}
		match CalendarValue.fractional_second(date, { hour: 23, minute: 59, second: 59 }, { value: fraction - 1, digits }) {
			Ok(value) => value
			Err(_) => crash "fixture fraction"
		}
	}
	qualified : CalendarValue, Bool -> QualifiedCalendarValue
	qualified = |description, all| {
		scopes = if all {
			[Whole, Year, Month, Day, Hour, Minute, Second, Fraction]
		} else {
			[]
		}
		match QualifiedCalendarValue.new(description, scopes.map(|scope| { scope, qualifier: UncertainApproximate })) {
			Ok(result) => result
			Err(_) => crash "fixture qualifications"
		}
	}
	envelope : Str, Str, Str -> Str
	envelope = |kind, profile, payload| Json.to_str({ format: "roc-time", version: "1", kind, profile, axis: "none", unit: "none", payload })
}
