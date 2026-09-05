app [main!] {
	time: "../../package/main.roc",
}

import time.PosixBoundary
import time.PosixDelta
import time.PosixSpan
import time.Coverage
import time.EventCollection

# Positive control for compile-failure checks: the same imports and valid
# domain combinations must succeed independently of application examples.
main! = |_args| {
	start = PosixBoundary.from_microseconds(0)
	end = PosixBoundary.shift(start, PosixDelta.from_microseconds(1))?
	span = PosixSpan.new(start, end)?
	_events = EventCollection.from_entries([{ id: 0.U64, span }])?
	_width = Coverage.coordinate_width(Coverage.from_spans([span]))?
	Ok({})
}
