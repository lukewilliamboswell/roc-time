import time.Coverage
import time.PosixBoundary
import time.PosixSpan

# R01/R04: a directly specified canonical list, including both I64 endpoints.
# count is bounded by the caller; interior endpoints remain within +/-20000.
IdentityFixture := [].{
	make = |count, shift| {
		if count == 0 {
			return Coverage.empty
		}
		var $spans = [span(-9223372036854775808, -9223372036854775807)]
		var $i = 0.U64
		while $i < count {
			lo = $i.to_i64_wrap() * 4 - 10000 + shift
			$spans = $spans.append(span(lo, lo + 1))
			$i = $i + 1
		}
		$spans = $spans.append(span(9223372036854775806, 9223372036854775807))
		Coverage.from_sorted_spans($spans) ?? crash "ordered disjoint fixture"
	}
}

span = |lo, hi| PosixSpan.new(PosixBoundary.from_microseconds(lo), PosixBoundary.from_microseconds(hi)) ?? crash "nonempty fixture"
