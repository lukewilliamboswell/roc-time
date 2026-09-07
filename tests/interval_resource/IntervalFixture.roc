import time.PosixBoundary
import time.PosixSpan

# R13/R15: n independent starts and n ends admit n*n nonempty intervals.
# A separate paired family is disconnected, exposing accidental hull queries.
IntervalFixture := [].{
	Inputs : { starts : List(PosixBoundary), ends : List(PosixBoundary), spans : List(PosixSpan) }
	inputs : U32 -> Inputs
	inputs = |n| {
		var $starts = []
		var $ends = []
		var $spans = []
		var $i = 0.I64
		while $i < n.to_i64() {
			$starts = $starts.append(PosixBoundary.from_microseconds(-($i) - 1))
			$ends = $ends.append(PosixBoundary.from_microseconds($i + 1))
			span = match PosixSpan.new(PosixBoundary.from_microseconds($i * 3), PosixBoundary.from_microseconds($i * 3 + 1)) {
				Ok(value) => value
				Err(_) => crash "bounded fixture span"
			}
			$spans = $spans.append(span)
			$i = $i + 1
		}
		{ starts: $starts, ends: $ends, spans: $spans }
	}
	sliced : Inputs, U32 -> Inputs
	sliced = |backing, n| {
		starts: List.sublist(backing.starts, { start: 1, len: n.to_u64() }),
		ends: List.sublist(backing.ends, { start: 1, len: n.to_u64() }),
		spans: List.sublist(backing.spans, { start: 1, len: n.to_u64() }),
	}
}
