import time.ZoneRules
import time.PosixBoundary
import time.PosixSpan
import time.FixedOffset

InterchangeFixture := [].{
	rules : U32 -> ZoneRules
	rules = |count| {
		var transitions = []
		var i = 1.U32
		while i <= count {
			transitions = transitions.append({
				at: PosixBoundary.from_microseconds(i.to_i64()),
				offset: FixedOffset.from_seconds(
					if U32.rem_by(i, 2) == 0 {
						0
					} else {
						3600
					},
				),
			})
			i = i + 1
		}
		validity = match PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(2000000 + count.to_i64())) {
			Ok(v) => v
			Err(_) => crash "fixture validity"
		}
		match ZoneRules.new("Fixture/Many", "resource-v1", validity, FixedOffset.from_seconds(0), transitions) {
			Ok(v) => v
			Err(_) => crash "fixture rules"
		}
	}
	text : U32 -> Str
	text = |tags| {
		var text = "1970-01-01T00:00:01Z[Fixture/Many]"
		var i = 0.U32
		while i < tags {
			text = "${text}[x${i.to_str()}=${"a".repeat(64)}]"
			i = i + 1
		}
		text
	}
}
