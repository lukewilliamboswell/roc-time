import time.NanoClockTime
import time.NanoLocalDateTime
import time.PosixNanoBoundary
import time.PosixNanoDelta

## The caller has decoded Arrow nanosecond values and retains nulls and column metadata.
NanosecondColumns :: [].{
	ClockCell : [ClockNanoseconds(I64), NullClock]
	Row : { opening : ClockCell, closing : ClockCell, zoned : { nanoseconds : I64, timezone : Str }, local : I64, displacement : I64 }

	## Use typed values and emit their exact source integers for export.
	report : Row -> Try(Str, _)
	report = |{ opening, closing, zoned, local, displacement }| {
		opening_text = clock_text(opening)?
		closing_text = clock_text(closing)?
		instant = PosixNanoBoundary.from_nanoseconds(zoned.nanoseconds)
		civil = NanoLocalDateTime.from_gregorian_local_nanoseconds(local)
		delta = PosixNanoDelta.from_nanoseconds(displacement)
		local_text = civil.to_gregorian_text()?
		local_count = civil.to_gregorian_local_nanoseconds()?
		Ok("Opening: ${opening_text}\nClosing: ${closing_text}\nTimestamp: ${instant.to_nanoseconds().to_str()} ns, zone metadata ${zoned.timezone}\nNaive: ${local_text} (${local_count.to_str()} ns)\nPOSIX displacement: ${delta.to_nanoseconds().to_str()} ns\n")
	}
}

clock_text : NanosecondColumns.ClockCell -> Try(Str, [OutOfRange])
clock_text = |cell| match cell {
	NullClock => Ok("null")
	ClockNanoseconds(number) => {
		clock = NanoClockTime.from_nanoseconds_since_midnight(number)?
		Ok("${clock.to_text()} (${clock.to_nanoseconds_since_midnight().to_str()} ns)")
	}
}
