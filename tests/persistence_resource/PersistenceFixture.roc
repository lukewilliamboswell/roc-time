import time.Coverage
import time.PosixSpan
import time.PosixBoundary

PersistenceFixture := [].{
	# Already materialized runtime input. Huge coordinate gaps are not members.
	coverage : U32, Bool -> Coverage
	coverage = |count, wide| {
		var $spans = []
		var $i = 0.U32
		while $i < count {
			start = if wide {
				I64.lowest + $i.to_i64() * 2
			} else {
				$i.to_i64() * 2
			}
			end = start + 1
			$spans = $spans.append(span(start, end))
			$i = $i + 1
		}
		Coverage.from_spans($spans)
	}
	span : I64, I64 -> PosixSpan
	span = |start, end| match PosixSpan.new(PosixBoundary.from_microseconds(start), PosixBoundary.from_microseconds(end)) {
		Ok(value) => value
		Err(_) => crash "resource fixture bounds"
	}
	oversized_json : U32 -> Str
	oversized_json = |count| {
		var $members = []
		var $i = 0.U32
		while $i < count {
			start = $i.to_i64() * 2
			$members = $members.append("${start.to_str()}/${(start + 1).to_str()}")
			$i = $i + 1
		}
		Json.to_str({ format: "roc-time", version: "1", kind: "coverage", profile: "posix-canonical-coverage-v1", axis: "posix-1970", unit: "microsecond", payload: Str.join_with($members, ";") })
	}
}
