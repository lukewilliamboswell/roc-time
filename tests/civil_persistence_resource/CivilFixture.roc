import time.ZoneRules
import time.PosixBoundary
import time.PosixSpan
import time.FixedOffset
import time.ResolvedBoundary
import time.ResolvedSelection
import time.Persistence

CivilFixture := [].{
	make = |count, boundary| {
		var transitions = []
		var i = 1.U32
		while i <= count {
			transitions = transitions.append({ at: PosixBoundary.from_microseconds(i.to_i64() * 1000000 - 500000), offset: FixedOffset.from_seconds(-i.to_i32_wrap()) })
			i = i + 1
		}
		validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest))?
		rules = ZoneRules.new_bounded("Synthetic/Folds", "resource-v1", validity, FixedOffset.from_seconds(0), transitions, { minimum: -count.to_i32_wrap(), maximum: 0 })?
		start = FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(0), Gregorian)?
		end = FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(1), Julian)?
		if boundary {
			result = ResolvedBoundary.resolve(rules, start, First)?
			Ok(ResolvedBoundary(result))
		} else {
			result = ResolvedSelection.resolve(rules, start, end)?
			Ok(ResolvedSelection(result))
		}
	}
}
