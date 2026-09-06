import time.ExactInterval
import time.Coverage

## Exchange exact booking windows as text, computing availability on coverage.
BookingExchange :: [].{
	available = |opening_text, booking_texts| {
		opening = parse(opening_text)?
		var bookings = []
		for text in booking_texts {
			bookings = bookings.append(ExactInterval.span(parse(text)?))
		}
		free = Coverage.complement_within(Coverage.from_spans(bookings), ExactInterval.span(opening))
		var output = []
		for span in free {
			# The application requests exact microsecond output in UTC. This
			# does not reconstruct the original bookings from merged coverage.
			value = match ExactInterval.from_span(span, UnassertedUtc, 6) {
				Ok(found) => found
				Err(error) => return Err(Output(error))
			}
			output = output.append(ExactInterval.to_text(value))
		}
		Ok(output)
	}
}

parse = |text| match ExactInterval.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Input(error))
}
