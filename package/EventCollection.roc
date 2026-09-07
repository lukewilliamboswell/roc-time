import Coverage
import PosixBoundary
import PosixSpan

## Events retain application-defined identity independently of their extents.
## Input order is preserved for iteration and contributor lists; it is not time order.
EventCollection(id) :: [Events(List({ id : id, span : PosixSpan }))].{

	## Expected O(n) construction for constant-cost ID hashing/equality; the
	## input list and ID payloads may remain shared.
	## One entry per identity. Duplicate IDs are errors, even for equal spans.
	from_entries : List({ id : id, span : PosixSpan }) -> Try(EventCollection(id), [DuplicateId(id), ..])
		where [id.is_eq : id, id -> Bool, id.to_hash : id, Hasher -> Hasher]
	from_entries = |entries| {
		var $seen = Dict.empty()
		for entry in entries {
			match Dict.get($seen, entry.id) {
				Ok(_) => return Err(DuplicateId(entry.id))
				Err(KeyNotFound) => {
					$seen = Dict.insert($seen, entry.id, {})
				}
			}
		}
		Ok(Events(entries))
	}

	event_count : EventCollection(id) -> U64
	event_count = |Events(entries)| entries.len()

	to_entries : EventCollection(id) -> List({ id : id, span : PosixSpan })
	to_entries = |Events(entries)| entries

	iter : EventCollection(id) -> Iter({ id : id, span : PosixSpan })
	iter = |Events(entries)| entries.iter()

	## Lossy projection: IDs and original segmentation cannot be recovered.
	to_coverage : EventCollection(id) -> Coverage
	to_coverage = |Events(entries)| Coverage.from_spans(entries.map(|entry| entry.span))

	## Retain each surviving identity once, with all of its clipped components.
	## Empty intersections are omitted. Output retains source event order.
	clip : EventCollection(id), Coverage -> List({ id : id, coverage : Coverage })
	clip = |Events(entries), window| {
		var $result = []
		for entry in entries {
			clipped = Coverage.intersection(Coverage.from_spans([entry.span]), window)
			if Coverage.member_count(clipped) > 0 {
				$result = $result.append({ id: entry.id, coverage: clipped })
			}
		}
		$result
	}

	## Partition occupied time at every event boundary. Each segment contains
	## exactly its active IDs, in source order. No per-microsecond enumeration.
	## O(n log n + n² + c) work, O(n + c) output/storage, where c counts emitted
	## contributor IDs. This scan is not an interval index or a coverage sweep.
	segments : EventCollection(id) -> List({ span : PosixSpan, contributors : List(id) })
	segments = |Events(entries)| {
		var $endpoints = []
		for entry in entries {
			$endpoints = $endpoints.append(PosixSpan.start(entry.span)).append(PosixSpan.end(entry.span))
		}
		sorted = $endpoints.sort_with(
			|a, b| match PosixBoundary.compare(a, b) {
				LT => Before
				EQ => Same
				GT => After
			},
		)
		var $previous = None
		var $result = []
		for boundary in sorted {
			match $previous {
				Some(start) => {
					if start < boundary {
						var $contributors = []
						for entry in entries {
							if PosixSpan.contains(entry.span, start) {
								$contributors = $contributors.append(entry.id)
							}
						}
						if !$contributors.is_empty() {
							# Sorted distinct boundaries establish the span invariant.
							span = match PosixSpan.new(start, boundary) {
								Ok(value) => value
								Err(_) => crash "Ordered event boundaries"
							}
							$result = $result.append({ span, contributors: $contributors })
						}
					}
				}
				None => {}
			}
			$previous = Some(boundary)
		}
		$result
	}

	## Constant-size diagnostics do not inspect application IDs or enumerate spans.
	to_inspect : EventCollection(id) -> Str
	to_inspect = |events| "EventCollection(events=${event_count(events).to_str()})"
}

test_eventcollection_span = |a, b| match PosixSpan.new(PosixBoundary.from_microseconds(a), PosixBoundary.from_microseconds(b)) {
	Ok(value) => value
	Err(_) => crash "Invalid test test_eventcollection_span"
}

expect {
	entries = [{ id: "booking-a", span: test_eventcollection_span(0, 2) }, { id: "booking-b", span: test_eventcollection_span(0, 2) }]
	events = EventCollection.from_entries(entries)?
	EventCollection.event_count(events) == 2 and
		Coverage.member_count(EventCollection.to_coverage(events)) == 1 and
			EventCollection.to_entries(events) == entries and
				EventCollection.segments(events) == [{ span: test_eventcollection_span(0, 2), contributors: ["booking-a", "booking-b"] }]
}

expect match EventCollection.from_entries([{ id: 1.U64, span: test_eventcollection_span(0, 1) }, { id: 1, span: test_eventcollection_span(2, 3) }]) {
	Err(DuplicateId(1)) => True
	_ => False
}

expect {
	events = EventCollection.from_entries([{ id: 8.U64, span: test_eventcollection_span(0, 10) }, { id: 9, span: test_eventcollection_span(3, 4) }])?
	windows = Coverage.from_spans([test_eventcollection_span(1, 2), test_eventcollection_span(8, 9)])
	EventCollection.clip(events, windows) == [{ id: 8, coverage: windows }]
}

expect {
	events = EventCollection.from_entries([{ id: 0.U64, span: test_eventcollection_span(0, 2) }, { id: 1, span: test_eventcollection_span(1, 3) }, { id: 2, span: test_eventcollection_span(2, 4) }])?
	EventCollection.segments(events) == [
		{ span: test_eventcollection_span(0, 1), contributors: [0] },
		{ span: test_eventcollection_span(1, 2), contributors: [0, 1] },
		{ span: test_eventcollection_span(2, 3), contributors: [1, 2] },
		{ span: test_eventcollection_span(3, 4), contributors: [2] },
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
	events = EventCollection.from_entries([{ id: 0.U64, span: test_eventcollection_span(I64.lowest, I64.highest) }])?
	EventCollection.segments(events) == [{ span: test_eventcollection_span(I64.lowest, I64.highest), contributors: [0] }]
}

# Independent bounded membership model, including overlap, touch and equal spans.
expect {
	var $good = True
	var $a = -2.I64
	while $a < 3 {
		var $b = $a + 1
		while $b <= 3 {
			var $c = -2.I64
			while $c < 3 {
				var $d = $c + 1
				while $d <= 3 {
					events = EventCollection.from_entries([{ id: 0.U64, span: test_eventcollection_span($a, $b) }, { id: 1, span: test_eventcollection_span($c, $d) }])?
					segments = EventCollection.segments(events)
					coverage = EventCollection.to_coverage(events)
					var $tick = -3.I64
					while $tick <= 3 {
						var $expected = []
						if $a <= $tick and $tick < $b {
							$expected = $expected.append(0.U64)
						}
						if $c <= $tick and $tick < $d {
							$expected = $expected.append(1.U64)
						}
						var $actual = []
						var $matches = 0.U64
						for segment in segments {
							low = PosixBoundary.to_microseconds(PosixSpan.start(segment.span))
							high = PosixBoundary.to_microseconds(PosixSpan.end(segment.span))
							if low <= $tick and $tick < high {
								$actual = segment.contributors
								$matches = $matches + 1
							}
						}
						$good = $good and $actual == $expected and $matches <= 1 and
							Coverage.contains(coverage, PosixBoundary.from_microseconds($tick)) == !$expected.is_empty()
						$tick = $tick + 1
					}
					$d = $d + 1
				}
				$c = $c + 1
			}
			$b = $b + 1
		}
		$a = $a + 1
	}
	$good
}
