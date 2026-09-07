import time.EventCollection
import time.Coverage
import time.CalendarDate
import time.ClockTime
import time.FixedOffset
import time.LocalDateTime
import time.PosixDelta
import time.PosixSpan

## Free room windows after overlapping bookings have been combined.
Availability :: { free : Coverage, bookings : EventCollection(Str) }.{
	Booking : { start : LocalDateTime, end : LocalDateTime, offset : FixedOffset }

	from_bookings : Booking, List({ id : Str, window : Booking }) -> Try(Availability, [EmptySpan, ReversedBounds, OutOfRange, DuplicateId(Str), ..])
	from_bookings = |opening, bookings| {
		work = resolve_booking(opening)?
		var $busy = []
		for booking in bookings {
			$busy = $busy.append({ id: booking.id, span: resolve_booking(booking.window)? })
		}
		events = EventCollection.from_entries($busy)?
		Ok({ free: Coverage.complement_within(EventCollection.to_coverage(events), work), bookings: events })
	}

	report : Availability -> Try(List(Str), [OutOfRange, ..])
	report = |available| {
		var $lines = ["Bookings retained: ${EventCollection.event_count(available.bookings).to_str()}"]
		for segment in EventCollection.segments(available.bookings) {
			if segment.contributors.len() > 1 {
				start = FixedOffset.project(FixedOffset.from_seconds(0), PosixSpan.start(segment.span), Gregorian)?
				end = FixedOffset.project(FixedOffset.from_seconds(0), PosixSpan.end(segment.span), Gregorian)?
				names = Str.join_with(segment.contributors, ", ")
				$lines = $lines.append("Booking conflict: ${names}, ${display(start)} to ${display(end)} (UTC)")
			}
		}
		for span in available.free {
			start = FixedOffset.project(FixedOffset.from_seconds(0), PosixSpan.start(span), Gregorian)?
			end = FixedOffset.project(FixedOffset.from_seconds(0), PosixSpan.end(span), Gregorian)?
			$lines = $lines.append("Free: ${display(start)} to ${display(end)} (UTC)")
		}
		width = PosixDelta.to_microseconds(Coverage.coordinate_width(available.free)?)
		Ok($lines.append("Total available: ${width.to_str()} microseconds of POSIX coordinate width"))
	}
}

resolve_booking = |booking| {
	start = FixedOffset.resolve(booking.offset, booking.start)?
	end = FixedOffset.resolve(booking.offset, booking.end)?
	PosixSpan.new(start, end)
}

# This application's minute-aligned display, not a general timestamp serializer.
display = |local| {
	date = CalendarDate.to_fields(LocalDateTime.date(local))
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	"${date.year.to_str()}-${pad(date.month)}-${pad(date.day)} ${pad(clock.hour)}:${pad(clock.minute)}"
}

pad = |n| if n < 10 {
	"0${n.to_str()}"
} else {
	n.to_str()
}
