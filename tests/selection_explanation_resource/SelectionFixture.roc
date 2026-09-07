import time.Coverage
import time.PosixSpan
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules

SelectionFixture := [].{
	coverage = |count, ownership| {
		var $spans = []
		var $i = 0.U32
		while $i < count + 2 {
			$spans = $spans.append(span($i.to_i64() * 2, $i.to_i64() * 2 + 1))
			$i = $i + 1
		}
		selected = if ownership == "sliced" {
			$spans.sublist({ start: 1, len: count.to_u64() })
		} else {
			$spans.sublist({ start: 0, len: count.to_u64() })
		}
		retained = if ownership == "owned" {
			None
		} else {
			Some($spans)
		}
		value = match Coverage.from_sorted_spans(selected) {
			Ok(v) => v
			Err(_) => crash "ordered fixture spans"
		}
		{ value, retained }
	}
	rules = |count, text_size| {
		var $transitions = []
		var $i = 0.U32
		while $i < count {
			$transitions = $transitions.append({ at: PosixBoundary.from_microseconds(-count.to_i64() + $i.to_i64()), offset: FixedOffset.from_seconds(0) })
			$i = $i + 1
		}
		match ZoneRules.new("Fixture/Selection", "é".repeat(text_size.to_u64()), span(I64.lowest, I64.highest), FixedOffset.from_seconds(0), $transitions) {
			Ok(v) => v
			Err(_) => crash "fixture rules"
		}
	}
}

span = |start, end| match PosixSpan.new(PosixBoundary.from_microseconds(start), PosixBoundary.from_microseconds(end)) {
	Ok(v) => v
	Err(_) => crash "fixture span"
}
