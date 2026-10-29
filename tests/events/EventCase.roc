import fuzz.Fuzz
import time.EventCollection
import time.Coverage
import time.PosixBoundary
import time.PosixSpan

Spec : { start : U8, width : U8 }

spec = { start: Fuzz.u8_in(0, 16), width: Fuzz.u8_in(1, 8) }.Fuzz

EventCase := { spans : List(Spec) }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(EventCase)
	generator_for = |_| Fuzz.map(
		Fuzz.list(spec, 12),
		|spans| { spans: spans },
	)

	## Typed seed mutations must stay inside the bounded model's input domain.
	## Malformed public values generated within that domain remain test cases.
	is_in_domain : EventCase -> Bool
	is_in_domain = |input| input.spans.len() <= 12 and input.spans.all(|span| span.start <= 16 and span.width >= 1 and span.width <= 8)

	check : EventCase -> Fuzz.Outcome
	check = |input| {
		if !is_in_domain(input) {
			return Fuzz.reject
		}
		entries = input.spans.map_with_index(
			|value, id| {
				{ id, span: make_span(value.start.to_i64() - 8, value.start.to_i64() - 8 + value.width.to_i64()) }
			},
		)
		events = match EventCollection.from_entries(entries) {
			Ok(value) => value
			Err(_) => crash "Unique IDs rejected"
		}
		if EventCollection.event_count(events) != entries.len() {
			crash "Event count lost identity"
		}
		var $iterated = []
		for event in events {
			$iterated = $iterated.append(event)
		}
		if $iterated != entries {
			crash "Event iteration changed source order"
		}
		partition = EventCollection.segments(events)
		projected = EventCollection.to_coverage(events)
		windows = Coverage.from_spans([make_span(-4, 0), make_span(2, 6)])
		clipped = EventCollection.clip(events, windows)
		var $tick = -9.I64
		while $tick <= 17 {
			var $expected = []
			var $index = 0.U64
			for value in input.spans {
				start = value.start.to_i64() - 8
				if start <= $tick and $tick < start + value.width.to_i64() {
					$expected = $expected.append($index)
				}
				$index = $index + 1
			}
			var $actual = []
			var $hits = 0.U64
			for segment in partition {
				low = PosixBoundary.to_microseconds(PosixSpan.start(segment.span))
				high = PosixBoundary.to_microseconds(PosixSpan.end(segment.span))
				if low <= $tick and $tick < high {
					$actual = segment.contributors
					$hits = $hits + 1
				}
			}
			if $actual != $expected or $hits > 1 {
				crash "Contributor partition differs from membership oracle"
			}
			if Coverage.contains(projected, point($tick)) != !$expected.is_empty() {
				crash "Coverage projection differs from event union"
			}
			var $clipped_ids = []
			for piece in clipped {
				if Coverage.contains(piece.coverage, point($tick)) {
					$clipped_ids = $clipped_ids.append(piece.id)
				}
			}
			inside = (-4 <= $tick and $tick < 0) or (2 <= $tick and $tick < 6)
			clipped_expected = if inside {
				$expected
			} else {
				[]
			}
			if $clipped_ids != clipped_expected {
				crash "Clipping lost or invented event contributors"
			}
			$tick = $tick + 1
		}
		# Retain the source list after operations to exercise shared ownership.
		if EventCollection.to_entries(events) != entries {
			crash "Event operation changed source"
		}
		match entries.get(0) {
			Ok(first) => match EventCollection.from_entries(entries.append(first)) {
				Err(DuplicateId(0)) => {}
				_ => crash "Duplicate identity accepted"
			}
			Err(_) => {}
		}
		Fuzz.keep
	}
}

point = |n| PosixBoundary.from_microseconds(n)

make_span = |a, b| match PosixSpan.new(point(a), point(b)) {
	Ok(value) => value
	Err(_) => crash "Invalid generated span"
}

## Model-domain admission keeps boundary cases and rejects unsupported mutations.
expect {
	boundary = EventCase.{ spans: [{ start: 16, width: 8 }] }
	{
		boundary_is_tested: EventCase.is_in_domain(boundary),
		outside_is_rejected: !EventCase.is_in_domain({ ..boundary, spans: [{ start: 16, width: 0 }] }),
	} == {
		boundary_is_tested: Bool.True,
		outside_is_rejected: Bool.True,
	}
}
