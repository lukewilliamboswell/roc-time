import Deadline
import time.PosixBoundary
import time.OffsetTimestamp

## R01/R02/R14/R16: the runner stages the application's actual Deadline module
## beside this check root. Runtime checks survive optimized builds.
DeadlineChecks :: [].{
	run = |zero, suffix| {
		if zero != 0 {
			crash "fixture requires runtime zero"
		}
		check_rounding(zero)
		for fixture in [
			{ now: -1.I64, expiry: "1970-01-01T00:00:00Z", checked: "1969-12-31T23:59:59.999999Z", end: "1970-01-01T00:00:00.000000Z", expired: False },
			{ now: 0, expiry: "1970-01-01T00:00:00Z", checked: "1970-01-01T00:00:00.000000Z", end: "1970-01-01T00:00:00.000000Z", expired: True },
			{ now: 1, expiry: "1970-01-01T00:00:00Z", checked: "1970-01-01T00:00:00.000001Z", end: "1970-01-01T00:00:00.000000Z", expired: True },
			{ now: -1000001, expiry: "1969-12-31T23:59:59Z", checked: "1969-12-31T23:59:58.999999Z", end: "1969-12-31T23:59:59.000000Z", expired: False },
			{ now: -1000000, expiry: "1969-12-31T23:59:59Z", checked: "1969-12-31T23:59:59.000000Z", end: "1969-12-31T23:59:59.000000Z", expired: True },
			{ now: -999999, expiry: "1969-12-31T23:59:59Z", checked: "1969-12-31T23:59:59.000001Z", end: "1969-12-31T23:59:59.000000Z", expired: True },
		] {
			now = PosixBoundary.from_microseconds(fixture.now)
			record = Deadline.evaluate(now, fixture.expiry)?
			if record.expired != fixture.expired or OffsetTimestamp.to_text(record.checked_at) != fixture.checked or OffsetTimestamp.to_text(record.expires_at) != fixture.end {
				crash "deadline independent field fixture"
			}
			expected = "{\"checked_at\":\"${fixture.checked}\",\"expired\":${
				if fixture.expired {
					"true"
				} else {
					"false"
				}
			},\"expires_at\":\"${fixture.end}\"}"
			if Deadline.encode(record) != expected {
				crash "deadline exact JSON fixture"
			}
			decoded = match Deadline.decode(expected) {
				Ok(value) => value
				Err(_) => crash "valid record rejected"
			}
			if decoded != record {
				crash "deadline decoded fields differ"
			}
		}
		raw_zero = zero.to_u128_wrap()
		if Deadline.acquire_positive_nanoseconds(raw_zero) != Err(UnavailableOrEpochClock) {
			crash "ambiguous platform zero accepted"
		}
		if Deadline.acquire_positive_nanoseconds(U128.highest - raw_zero) != Err(OutOfRange) or Deadline.acquire_positive_nanoseconds(I128.highest.to_u128_wrap() - raw_zero) != Err(OutOfRange) {
			crash "clock acquisition overflow"
		}
		if Deadline.acquire_positive_nanoseconds(999999999 + raw_zero) != Ok(PosixBoundary.from_microseconds(999999)) {
			crash "positive acquisition floor"
		}
		if Deadline.acquire_positive_nanoseconds(1 + raw_zero) != Ok(PosixBoundary.from_microseconds(0)) {
			crash "positive submicrosecond acquisition floor"
		}
		if Deadline.evaluate(PosixBoundary.from_microseconds(I64.highest - zero.to_i64_wrap()), "1970-01-01T00:00:00Z") != Err(Output(OutOfRange)) {
			crash "timestamp output range hidden"
		}
		if Deadline.evaluate(PosixBoundary.from_microseconds(0), "not-a-timestamp${suffix}") != Err(Expiry(Malformed)) {
			crash "malformed expiry error hidden"
		}
		if Deadline.decode("{\"checked_at\":\"not-a-timestamp${suffix}\",\"expired\":true,\"expires_at\":\"1970-01-01T00:00:00Z\"}") != Err(InvalidOffsetTimestamp(Malformed)) {
			crash "malformed record timestamp error hidden"
		}
		match Deadline.decode("{${suffix}") {
			Err(InvalidJson(_)) => {}
			_ => crash "malformed JSON error hidden"
		}
		if Deadline.decode("{\"checked_at\":\"1970-01-01T00:00:00Z\",\"expired\":false,\"expires_at\":\"1970-01-01T00:00:00Z\"}${suffix}") != Err(InconsistentStatus) {
			crash "inconsistent expired status accepted"
		}
		Ok({})
	}
}

# Independent integer expectations in nanoseconds and microseconds. These are
# unit conversion/rounding laws, not outputs generated from package functions.
check_rounding = |zero| {
	for fixture in [
		{ ns: -1500.I128, floor: -2.I64, ceiling: -1.I64, trunc: -1.I64, even: -2.I64 },
		{ ns: -500, floor: -1, ceiling: 0, trunc: 0, even: 0 },
		{ ns: 500, floor: 0, ceiling: 1, trunc: 0, even: 0 },
		{ ns: 1500, floor: 1, ceiling: 2, trunc: 1, even: 2 },
		{ ns: 999999500, floor: 999999, ceiling: 1000000, trunc: 999999, even: 1000000 },
	] {
		input = fixture.ns + zero
		if PosixBoundary.from_nanoseconds(input) != Err(Submicrosecond) {
			crash "precision rejection"
		}
		if PosixBoundary.from_nanoseconds_with_rounding(input, Floor) != Ok(PosixBoundary.from_microseconds(fixture.floor)) or
			PosixBoundary.from_nanoseconds_with_rounding(input, Ceiling) != Ok(PosixBoundary.from_microseconds(fixture.ceiling)) or
				PosixBoundary.from_nanoseconds_with_rounding(input, TowardZero) != Ok(PosixBoundary.from_microseconds(fixture.trunc)) or
					PosixBoundary.from_nanoseconds_with_rounding(input, NearestTiesEven) != Ok(PosixBoundary.from_microseconds(fixture.even)) {
			crash "independent decimal rounding fixture"
		}
	}
	for input in [I128.lowest + zero, I128.highest - zero] {
		if PosixBoundary.from_nanoseconds_with_rounding(input, TowardZero) != Err(OutOfRange) {
			crash "wide coordinate overflow"
		}
	}
	for value in [I64.lowest, I64.highest] {
		input = value.to_i128() * 1000 + zero
		if PosixBoundary.from_nanoseconds(input) != Ok(PosixBoundary.from_microseconds(value)) {
			crash "exact coordinate limit"
		}
	}
}
