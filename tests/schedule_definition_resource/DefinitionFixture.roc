import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.FixedOffset
import time.ZoneRules

DefinitionFixture := [].{
	label = |day| {
		boundary = PosixBoundary.from_microseconds(946684800000001 + day * 86400000000)
		match FixedOffset.project(FixedOffset.from_seconds(0), { boundary, calendar: Gregorian }) {
			Ok(value) => value
			Err(_) => crash "bounded resource label"
		}
	}
	inputs = |count| {
		var $entries = []
		var $index = 0.U64
		while $index < count {
			day = if $index < 2 {
				0.I64
			} else {
				$index.to_i64_wrap() - 1
			}
			$entries = $entries.append({ source: label(day), ending: After(Coordinate(PosixDelta.from_microseconds(7200000000))) })
			$index = $index + 1
		}
		$entries
	}
	rules = |_| {
		validity = PosixSpan.new({ start: PosixBoundary.from_microseconds(I64.lowest), end: PosixBoundary.from_microseconds(I64.highest) }) ?? crash "ordered validity"
		ZoneRules.Provider.new_bounded({ name: "Synthetic/Definition", version: "fixed-v1", validity, initial: FixedOffset.from_seconds(0), transitions: [], bounds: { minimum: 0, maximum: 0 } }) ?? crash "valid fixed rules"
	}
}
