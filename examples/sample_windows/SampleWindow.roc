import time.PosixSpan

## The recorder treats each sample window as a nonempty half-open span.
SampleWindow :: { span : PosixSpan }.{
	from_seconds : Dec, Dec -> Try(SampleWindow, [EmptySpan, ReversedBounds, Submicrosecond, OutOfRange, ..])
	from_seconds = |start, end| {
		Ok({ span: PosixSpan.from_seconds(start, end, RejectSubmicrosecond)? })
	}

	handoff_report : SampleWindow, SampleWindow -> Str
	handoff_report = |first, next| {
		if PosixSpan.overlaps(first.span, next.span) {
			"Sample windows overlap: inspect the recorder for duplicate acquisition."
		} else if PosixSpan.relation(first.span, next.span) == Meets {
			"Continuous acquisition: the windows touch without duplicate coverage."
		} else {
			"Sample windows are disconnected or out of order: inspect the recorder handoff."
		}
	}
}
