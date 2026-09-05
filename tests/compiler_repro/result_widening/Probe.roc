import time.GregorianDate
Probe :: [].{
	identity : GregorianDate -> Try(GregorianDate, [OutOfRange, InvalidDestination(GregorianDate.Fields), ..])
	identity = |date| {
		fields = GregorianDate.to_fields(date)
		year = narrow_year(I64.to_i128(fields.year))?
		if year != fields.year {
			crash "wrong narrowed year"
		}
		Ok(date)
	}
}

narrow_year : I128 -> Try(I64, [OutOfRange, ..])
narrow_year = |year| {
	if year < -2147483648 or year > 2147483647 {
		return Err(OutOfRange)
	}
	I128.to_i64_try(year)
}
