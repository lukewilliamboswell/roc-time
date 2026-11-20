import time.ExactInterval
import time.Coverage

## Exchange exact booking windows as text, computing availability on coverage.
BookingExchange :: [].{
	available = |opening_text, booking_texts| {
		opening = parse(opening_text)?
		bookings = booking_texts.map_try(
			|source| {
				booking = parse(source)?
				Ok(booking.span())
			},
		)?
		computed = Coverage.complement_within(Coverage.from_spans(bookings), opening.span())
		var $output = []
		for span in computed {
			# The application requests exact microsecond output in UTC. This
			# does not reconstruct the original bookings from merged coverage.
			value = match ExactInterval.from_span(span, { offset: UnassertedUtc, fraction_digits: 6 }) {
				Ok(found) => found
				Err(error) => return Err(Output(error))
			}
			$output = $output.append(ExactInterval.to_text(value))
		}
		Ok($output)
	}
}

parse = |text| match ExactInterval.parse(text) {
	Ok(value) => Ok(value)
	Err(error) => Err(Input(error))
}
