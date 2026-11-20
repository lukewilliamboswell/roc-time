import time.Coverage
import time.PosixBoundary
import time.PosixSpan

## Resolved availability in repeating half-open blocks. Independent expectations
## enumerate bounded integer positions and group runs with equal membership.
CoverageWorkload := [].{
	Shape : [Sparse, Dense, Disjoint]
	Mode : [Sorted, Unsorted, RejectUnsorted, Union, Intersection, Difference, Contains, FoldOverlap, MaterializeOverlap]
	Output : [Spans(List(PosixSpan)), UnsortedInput, Point(Bool), Folded({ count : U64, endpoints : U64 })]

	Fixture : {
		left_spans : List(PosixSpan),
		reversed : List(PosixSpan),
		left : Coverage,
		right : Coverage,
		point : PosixBoundary,
		query : PosixSpan,
		expected : Output,
	}

	prepare : { count : U64, shape : Shape, matches : U64, mode : Mode, phase : U64 } -> Fixture
	prepare = |{ count, shape, matches, mode, phase }| {
		dense = shape == Dense
		blocks = if (dense) count // 2 else count
		width = if (dense) 8.U64 else 4
		right_start = if (shape == Disjoint) 8.U64 else width // 2

		var $raw = [span(0, 4)]
		var $right = []
		var $index = 0.U64
		while $index < count {
			start = phase + if (dense) 16 * ($index // 2) + 4 * ($index % 2) else 16 * $index
			$raw = $raw.append(span(start + 16, start + 20))
			$right = $right.append(span(start + 16 + right_start, start + 20 + right_start))
			$index = $index + 1
		}
		$raw = $raw.append(span(16 * (count + 1) + phase, 16 * (count + 1) + phase + 4))
		left_spans = $raw.sublist({ start: 1, len: count })
		left = Coverage.from_sorted_spans(left_spans) ?? crash "sorted fixture"
		right = Coverage.from_sorted_spans($right) ?? crash "sorted fixture"
		last = 16 * blocks + phase
		lo = if (matches == 0) last + width else 16 * (blocks - matches + 1) + phase
		hi = if (matches == 0) lo + 1 else last + width
		point = bound(lo)
		query = span(lo, hi)

		expected_spans = model({
			blocks,
			phase,
			width,
			right_start,
			lo,
			hi,
			mode,
		})
		expected = match mode {
			Contains => Point(matches > 0)
			FoldOverlap => Folded(fold_spans(expected_spans))
			RejectUnsorted if count >= 2 => UnsortedInput
			_ => Spans(expected_spans)
		}
		reversed = left_spans.map_with_index(|_, index| left_spans.get(count - 1 - index) ?? crash "fixture index")
		{ left_spans, left, right, point, query, expected, reversed }
	}

	sorted : List(PosixSpan) -> Output
	sorted = |spans| match Coverage.from_sorted_spans(spans) {
		Ok(value) => Spans(Coverage.to_spans(value))
		Err(UnsortedInput) => UnsortedInput
	}

	fold : (Coverage, PosixSpan) -> Output
	fold = |(coverage, window)| Folded(
		Coverage.fold_overlaps(
			coverage,
			{
				query: window,
				initial: { count: 0, endpoints: 0 },
				step: observe,
			},
		),
	)

	checksum : Output -> U64
	checksum = |output| match output {
		Spans(spans) => {
			folded = fold_spans(spans)
			1 + folded.count + folded.endpoints
		}
		UnsortedInput => 3
		Point(True) => 2
		Point(False) => 1
		Folded({ count, endpoints }) => 1 + count + endpoints
	}

}

bound = |value| PosixBoundary.from_microseconds(value.to_i64_wrap())

span = |start, end| PosixSpan.new({ start: bound(start), end: bound(end) }) ?? crash "valid fixture span"

observe = |state, member| {
	start = PosixBoundary.to_microseconds(PosixSpan.start(member)).to_u64_wrap()
	end = PosixBoundary.to_microseconds(PosixSpan.end(member)).to_u64_wrap()
	{ count: state.count + 1, endpoints: state.endpoints + start + end }
}

fold_spans = |values| values.fold({ count: 0, endpoints: 0 }, observe)

model = |{ blocks, phase, width, right_start, lo, hi, mode }| {
	var $expected = []
	var $start = None
	# The final point lies outside either operand and closes the last run.
	for position in (16.U64).to(16 * (blocks + 1)) {
		point = position + phase
		lane = position % 16
		inside = position // 16 <= blocks
		left = inside and lane < width
		right = inside and lane >= right_start and lane < right_start + width
		include = match mode {
			Union => left or right
			Intersection => left and right
			Difference => left and !right
			FoldOverlap | MaterializeOverlap => {
				start = point - lane
				left and start < hi and start + width > lo
			}
			_ => left
		}
		match (include, $start) {
			(True, None) => {
				$start = Some(point)
			}
			(False, Some(start)) => {
				$expected = $expected.append(span(start, point))
				$start = None
			}
			_ => {}
		}
	}
	$expected
}
