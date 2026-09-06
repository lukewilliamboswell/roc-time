import time.ZoneRules
import time.PosixBoundary
import time.PosixSpan
import time.FixedOffset

ExplanationFixture := [].{
	rules : U32, U32 -> ZoneRules
	rules = |count, text_size| {
		version = "é".repeat(text_size.to_u64())
		var $transitions = []
		var $i = 1.U32
		while $i <= count {
			$transitions = $transitions.append({
				at: PosixBoundary.from_microseconds($i.to_i64()),
				offset: FixedOffset.from_seconds(
					if U32.rem_by($i, 2) == 0 {
						0
					} else {
						3600
					},
				),
			})
			$i = $i + 1
		}
		validity = match PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(2000000 + count.to_i64())) {
			Ok(v) => v
			Err(_) => crash "fixture validity"
		}
		match ZoneRules.new("Fixture/Explanation", version, validity, FixedOffset.from_seconds(0), $transitions) {
			Ok(v) => v
			Err(_) => crash "fixture rules"
		}
	}
}
