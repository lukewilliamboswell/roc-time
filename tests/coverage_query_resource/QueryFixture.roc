import time.Coverage
import time.PosixBoundary
import time.PosixSpan

QueryFixture := [].{
	prepare = |count, matches| {
		var $retained = []
		var $index = 0.U64
		while $index < count + 2 {
			$retained = $retained.append(span_at($index))
			$index = $index + 1
		}
		slice = $retained.sublist({ start: 1, len: count })
		coverage = Coverage.from_sorted_spans(slice) ?? crash "sorted fixture"
		# Spans start 16µs apart and each has width four. Select the last
		# matches, or a gap that touches the last span's exclusive end.
		first = if (matches == 0) count else count - matches + 1
		point = if (matches == 0) lower(first) + 4 else lower(first)
		upper = if (matches == 0) point + 12 else lower(count) + 4
		query = bounds(point, upper)
		members = slice.drop_first(count - matches)
		# Sum (2 * start + 4) for each consecutive member of the progression.
		n = matches.to_i64_wrap()
		endpoints = n * (2 * lower(first) + 4) + 16 * n * (n - 1)
		{ coverage, query, point, members, retained: $retained, expected: { count: matches, endpoints } }
	}

	span_at = |index| bounds(lower(index), lower(index) + 4)

	observe = |state, span| {
		start = PosixBoundary.to_microseconds(PosixSpan.start(span))
		finish = PosixBoundary.to_microseconds(PosixSpan.end(span))
		{ count: state.count + 1, endpoints: state.endpoints + start + finish }
	}
}

lower = |index| index.to_i64_wrap() * 16 - 32768

bounds = |start, end| PosixSpan.new({
	start: PosixBoundary.from_microseconds(start),
	end: PosixBoundary.from_microseconds(end),
}) ?? crash "nonempty fixture"
