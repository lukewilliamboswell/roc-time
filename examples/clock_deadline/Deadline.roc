import time.OffsetTimestamp
import time.PosixBoundary

## Pure expiry checks over supplied POSIX coordinates. This is wall-clock
## validity, not a monotonic timer or a physical elapsed-time measurement.
Deadline :: [].{
	Record : { checked_at : OffsetTimestamp, expires_at : OffsetTimestamp, expired : Bool }
	DecodeError : [InvalidJson(Str), MissingRequiredField(Str), Encoding([InvalidJson(Str)]), InvalidOffsetTimestamp(OffsetTimestamp.Error), OutOfRange, InconsistentStatus]

	## basic-cli 0.26.0 reports signed epoch nanoseconds, negative before 1970,
	## and saturates an unrepresentable clock at the I128 limit, which is rejected
	## here as out of range. Floor is explicit precision reduction.
	acquire_nanoseconds : I128 -> Try(PosixBoundary, [OutOfRange, Submicrosecond])
	acquire_nanoseconds = |nanos| PosixBoundary.from_nanoseconds_with_rounding(nanos, Floor)

	## Store both positions as UTC timestamps with six fractional digits.
	evaluate : PosixBoundary, Str -> Try(Record, [Expiry(OffsetTimestamp.Error), Output(OffsetTimestamp.Error), OutOfRange])
	evaluate = |now, expiry_text| {
		expiry = match OffsetTimestamp.parse(expiry_text) {
			Ok(value) => value
			Err(error) => return Err(Expiry(error))
		}
		end = OffsetTimestamp.boundary(expiry)?
		checked_at = match OffsetTimestamp.from_boundary(now, UnassertedUtc, 6) {
			Ok(value) => value
			Err(error) => return Err(Output(error))
		}
		expires_at = match OffsetTimestamp.from_boundary(end, UnassertedUtc, 6) {
			Ok(value) => value
			Err(error) => return Err(Output(error))
		}
		Ok({ checked_at, expires_at, expired: now >= end })
	}

	encode : Record -> Str
	encode = |record| Json.to_str(record)

	## Decode timestamp strings through their checked generic codecs. A saved
	## status must agree with the supplied readings; it does not read today's clock.
	decode : Str -> Try(Record, DecodeError)
	decode = |text| {
		record : Record
		record = Json.parse(text)?
		checked = OffsetTimestamp.boundary(record.checked_at)?
		end = OffsetTimestamp.boundary(record.expires_at)?
		if record.expired != (checked >= end) {
			return Err(InconsistentStatus)
		}
		Ok(record)
	}
}
