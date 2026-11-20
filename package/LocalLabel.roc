import Calendar
import GregorianDate

LocalLabel :: [].{
	parse : Str, (Str -> Try(clock, [Incomplete, ..errors])) -> Try({ date : Calendar.Date, clock : clock }, [TooLarge, Incomplete, Malformed, InvalidDate(GregorianDate.Error), InvalidTime([Incomplete, ..errors])])
	parse = |text, parse_clock| {
		if text.count_utf8_bytes() > 64 {
			return Err(TooLarge)
		}
		(date_text, clock_text) = match text.split_on("T") {
			[a, b] => (a, b)
			[a] => {
				return match GregorianDate.parse(a) {
					Ok(_) => Err(Incomplete)
					Err(Incomplete) => Err(Incomplete)
					Err(error) => Err(InvalidDate(error))
				}
			}
			_ => return Err(Malformed)
		}
		day = match GregorianDate.parse(date_text) {
			Ok(value) => value
			# A separator after a partial date cannot become valid by appending.
			Err(Incomplete) => return Err(InvalidDate(Malformed))
			Err(error) => return Err(InvalidDate(error))
		}
		time = match parse_clock(clock_text) {
			Ok(value) => value
			Err(Incomplete) => return Err(Incomplete)
			Err(error) => return Err(InvalidTime(error))
		}
		Ok({ date: Calendar.Date.from_gregorian(day), clock: time })
	}
}
