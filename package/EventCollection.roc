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
		var seen = Dict.empty()
		for entry in entries {
			match Dict.get(seen, entry.id) {
				Ok(_) => return Err(DuplicateId(entry.id))
				Err(KeyNotFound) => {
					seen = Dict.insert(seen, entry.id, {})
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
		var result = []
		for entry in entries {
			clipped = Coverage.intersection(Coverage.from_spans([entry.span]), window)
			if Coverage.member_count(clipped) > 0 {
				result = result.append({ id: entry.id, coverage: clipped })
			}
		}
		result
	}

	## Partition occupied time at every event boundary. Each segment contains
	## exactly its active IDs, in source order. No per-microsecond enumeration.
	## O(n log n + n² + c) work, O(n + c) output/storage, where c counts emitted
	## contributor IDs. This scan is not an interval index or a coverage sweep.
	segments : EventCollection(id) -> List({ span : PosixSpan, contributors : List(id) })
	segments = |Events(entries)| {
		var endpoints = []
		for entry in entries {
			endpoints = endpoints.append(PosixSpan.start(entry.span)).append(PosixSpan.end(entry.span))
		}
		sorted = endpoints.sort_with(
			|a, b| match PosixBoundary.compare(a, b) {
				LT => Before
				EQ => Same
				GT => After
			},
		)
		var previous = None
		var result = []
		for boundary in sorted {
			match previous {
				Some(start) => {
					if start < boundary {
						var contributors = []
						for entry in entries {
							if PosixSpan.contains(entry.span, start) {
								contributors = contributors.append(entry.id)
							}
						}
						if !contributors.is_empty() {
							# Sorted distinct boundaries establish the span invariant.
							span = match PosixSpan.new(start, boundary) {
								Ok(value) => value
								Err(_) => crash "Ordered event boundaries"
							}
							result = result.append({ span, contributors })
						}
					}
				}
				None => {}
			}
			previous = Some(boundary)
		}
		result
	}

	## Constant-size diagnostics do not inspect application IDs or enumerate spans.
	to_inspect : EventCollection(id) -> Str
	to_inspect = |events| "EventCollection(events=${event_count(events).to_str()})"
}
