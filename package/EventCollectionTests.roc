import EventCollection
import Coverage
import PosixBoundary
import PosixSpan

EventCollectionTests :: [].{}

span = |a, b| match PosixSpan.new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b)) {
	Ok(value) => value
	Err(_) => crash "Invalid test span"
}

expect {
	entries = [{ id: "booking-a", span: span(0, 2) }, { id: "booking-b", span: span(0, 2) }]
	events = EventCollection.from_entries(entries)?
	EventCollection.event_count(events) == 2 and
		Coverage.member_count(EventCollection.to_coverage(events)) == 1 and
			EventCollection.to_entries(events) == entries and
				EventCollection.segments(events) == [{ span: span(0, 2), contributors: ["booking-a", "booking-b"] }]
}

expect match EventCollection.from_entries([{ id: 1.U64, span: span(0, 1) }, { id: 1, span: span(2, 3) }]) {
	Err(DuplicateId(1)) => True
	_ => False
}

expect {
	events = EventCollection.from_entries([{ id: 8.U64, span: span(0, 10) }, { id: 9, span: span(3, 4) }])?
	windows = Coverage.from_spans([span(1, 2), span(8, 9)])
	EventCollection.clip(events, windows) == [{ id: 8, coverage: windows }]
}

expect {
	events = EventCollection.from_entries([{ id: 0.U64, span: span(0, 2) }, { id: 1, span: span(1, 3) }, { id: 2, span: span(2, 4) }])?
	EventCollection.segments(events) == [
		{ span: span(0, 1), contributors: [0] },
		{ span: span(1, 2), contributors: [0, 1] },
		{ span: span(2, 3), contributors: [1, 2] },
		{ span: span(3, 4), contributors: [2] },
	]
}

expect {
	empty : EventCollection(U64)
	empty = EventCollection.from_entries([])?
	EventCollection.event_count(empty) == 0 and EventCollection.segments(empty) == [] and
		EventCollection.to_coverage(empty) == Coverage.empty and
			Str.inspect(empty) == "EventCollection(events=0)"
}

expect {
	events = EventCollection.from_entries([{ id: 0.U64, span: span(I64.lowest, I64.highest) }])?
	EventCollection.segments(events) == [{ span: span(I64.lowest, I64.highest), contributors: [0] }]
}

# Independent bounded membership model, including overlap, touch and equal spans.
expect {
	var good = True
	var a = -2.I64
	while a < 3 {
		var b = a + 1
		while b <= 3 {
			var c = -2.I64
			while c < 3 {
				var d = c + 1
				while d <= 3 {
					events = EventCollection.from_entries([{ id: 0.U64, span: span(a, b) }, { id: 1, span: span(c, d) }])?
					segments = EventCollection.segments(events)
					coverage = EventCollection.to_coverage(events)
					var tick = -3.I64
					while tick <= 3 {
						var expected = []
						if a <= tick and tick < b {
							expected = expected.append(0.U64)
						}
						if c <= tick and tick < d {
							expected = expected.append(1.U64)
						}
						var actual = []
						var matches = 0.U64
						for segment in segments {
							low = PosixBoundary.to_microseconds(PosixSpan.start(segment.span))
							high = PosixBoundary.to_microseconds(PosixSpan.end(segment.span))
							if low <= tick and tick < high {
								actual = segment.contributors
								matches = matches + 1
							}
						}
						good = good and actual == expected and matches <= 1 and
							Coverage.contains(coverage, PosixBoundary.from_microseconds(tick)) == !expected.is_empty()
						tick = tick + 1
					}
					d = d + 1
				}
				c = c + 1
			}
			b = b + 1
		}
		a = a + 1
	}
	good
}
