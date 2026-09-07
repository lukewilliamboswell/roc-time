import time.OffsetTimestamp
import time.PosixBoundary

## Pure expiry checks over supplied POSIX coordinates. This is wall-clock
## validity, not a monotonic timer or a physical elapsed-time measurement.
Deadline :: [].{
	Record : { checked_at : OffsetTimestamp, expires_at : OffsetTimestamp, expired : Bool }
	DecodeError : [InvalidJson(Str), MissingRequiredField(Str), Encoding([InvalidJson(Str)]), InvalidOffsetTimestamp(OffsetTimestamp.Error), OutOfRange, InconsistentStatus]

	## basic-cli 0.22.2 replaces a pre-epoch clock error with zero. This app
	## Source: basic-cli revision 23622ee334755e18118bfc885a20f53fa4a16d66,
	## platform/Utc.roc (wrapper) and src/lib.rs (host clock error).
	## requires a positive current-epoch reading and rejects that ambiguous zero.
	## The bridge cannot distinguish a genuine epoch from the platform fallback.
	## Floor is explicit precision reduction; the core retains signed input APIs.
	acquire_positive_nanoseconds : U128 -> Try(PosixBoundary, [UnavailableOrEpochClock, OutOfRange, Submicrosecond, ..])
	acquire_positive_nanoseconds = |raw| {
		if raw == 0 {
			return Err(UnavailableOrEpochClock)
		}
		signed = match U128.to_i128_try(raw) {
			Ok(value) => value
			Err(_) => return Err(OutOfRange)
		}
		PosixBoundary.from_nanoseconds_with_rounding(signed, Floor)
	}

	## Store both positions as UTC timestamps with six fractional digits.
	evaluate : PosixBoundary, Str -> Try(Record, [Expiry(OffsetTimestamp.Error), Output(OffsetTimestamp.Error), OutOfRange, ..])
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
