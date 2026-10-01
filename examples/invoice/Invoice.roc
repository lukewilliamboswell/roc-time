import time.Calendar
import time.GregorianDate

## This merchant's payment terms clamp a missing due-day to month end.
Invoice :: { issued : GregorianDate, due : GregorianDate }.{
	with_monthly_terms : GregorianDate, I64 -> Try(Invoice, [OutOfRange, InvalidDestination(GregorianDate.Fields), NegativeTerm, ..])
	with_monthly_terms = |issued, months| {
		if months < 0 {
			return Err(NegativeTerm)
		}
		due = Calendar.Arithmetic.shift_day(issued, Calendar.Delta.months(months), Clamp)?
		Ok({ issued, due })
	}

	report : Invoice -> Str
	report = |invoice| {
		"Issued: ${GregorianDate.to_text(invoice.issued)}\nPayment due: ${GregorianDate.to_text(invoice.due)}\n"
	}
}
