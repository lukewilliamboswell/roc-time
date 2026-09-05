import time.CalendarArithmetic
import time.CalendarDelta
import time.GregorianDate

## This merchant's payment terms clamp a missing due-day to month end.
Invoice :: { issued : GregorianDate, due : GregorianDate }.{
	with_monthly_terms : GregorianDate.Fields, I64 -> Try(Invoice, [OutOfRange, InvalidMonth, InvalidDay, InvalidDestination(GregorianDate.Fields), NegativeTerm, ..])
	with_monthly_terms = |issued_fields, months| {
		if months < 0 {
			return Err(NegativeTerm)
		}
		issued = GregorianDate.from_fields(issued_fields)?
		due = CalendarArithmetic.shift_day(issued, CalendarDelta.months(months), Clamp)?
		Ok({ issued, due })
	}

	report : Invoice -> Str
	report = |invoice| {
		"Issued: ${display(invoice.issued)}\nPayment due: ${display(invoice.due)}\n"
	}
}

display = |date| {
	fields = GregorianDate.to_fields(date)
	"${fields.year.to_str()}-${two_digits(fields.month)}-${two_digits(fields.day)}"
}

two_digits = |value| if value < 10.U8 {
	"0${value.to_str()}"
} else {
	value.to_str()
}
