import MicrosecondRounding
import PosixNanoDelta
import PosixNanoBoundary
import NanoLocalDateTime
import NanoClockTime

## Work with nanosecond values and explicit precision reduction.
Nanosecond :: [].{

	## MicrosecondRounding operations and types.
	Rounding : MicrosecondRounding

	## PosixNanoDelta operations and types.
	PosixDelta : PosixNanoDelta

	## PosixNanoBoundary operations and types.
	PosixBoundary : PosixNanoBoundary

	## NanoLocalDateTime operations and types.
	LocalDateTime : NanoLocalDateTime

	## NanoClockTime operations and types.
	ClockTime : NanoClockTime

}
