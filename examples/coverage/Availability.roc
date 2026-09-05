import time.Coverage
import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan

## Free room windows after overlapping bookings have been combined.
Availability :: { free : Coverage }.{
	Booking : { start : Dec, end : Dec }

	from_bookings : Booking, List(Booking) -> Try(Availability, [EmptySpan, ReversedBounds, Submicrosecond, OutOfRange, ..])
	from_bookings = |opening, bookings| {
		work = PosixSpan.from_seconds(opening.start, opening.end, RejectSubmicrosecond)?
		var busy = []
		for booking in bookings {
			busy = busy.append(PosixSpan.from_seconds(booking.start, booking.end, RejectSubmicrosecond)?)
		}
		Ok({ free: Coverage.complement_within(Coverage.from_spans(busy), work) })
	}

	report : Availability -> Try(List(Str), [OutOfRange, ..])
	report = |available| {
		var lines = []
		for span in available.free {
			# Present exact epoch microseconds; calendar formatting is not implemented yet.
			start = PosixBoundary.to_microseconds(PosixSpan.start(span))
			end = PosixBoundary.to_microseconds(PosixSpan.end(span))
			lines = lines.append("Free: [${start.to_str()}, ${end.to_str()}) POSIX microseconds")
		}
		width = PosixDelta.to_microseconds(Coverage.coordinate_width(available.free)?)
		Ok(lines.append("Total available: ${width.to_str()} microseconds of POSIX coordinate width"))
	}
}
