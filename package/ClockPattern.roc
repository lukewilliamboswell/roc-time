import ClockTime

## Ordered clock candidates within one civil day. Empty selector lists inherit
## the anchor field; explicit selectors expand it. Microseconds stay anchored.
## This is a candidate layer, not a recurrence rule or timezone interpretation.
ClockPattern :: { hours : List(U8), minutes : List(U8), seconds : List(U8), microsecond : U32 }.{
	Spec : { hours : List(U8), minutes : List(U8), seconds : List(U8) }

	## O(s log s) construction, with at most 4096 supplied values per field.
	## Retains at most 144 distinct field values, shared by its iterators.
	new : ClockTime, Spec -> Try(ClockPattern, [TooManySelectors, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, ..])
	new = |anchor, spec| {
		if spec.hours.len() > 4096 or spec.minutes.len() > 4096 or spec.seconds.len() > 4096 {
			return Err(TooManySelectors)
		}
		for hour in spec.hours {
			if hour > 23 {
				return Err(InvalidHour)
			}
		}
		for minute in spec.minutes {
			if minute > 59 {
				return Err(InvalidMinute)
			}
		}
		for second in spec.seconds {
			if second == 60 {
				return Err(UnsupportedLeapSecond)
			}
			if second > 59 {
				return Err(InvalidSecond)
			}
		}
		fields = ClockTime.to_fields(anchor)
		Ok({ hours: normalize(spec.hours, fields.hour), minutes: normalize(spec.minutes, fields.minute), seconds: normalize(spec.seconds, fields.second), microsecond: fields.microsecond })
	}

	## Effective normalized fields, including inherited defaults. These are not
	## the original selector spelling and do not materialize clock combinations.
	definition : ClockPattern -> { hours : List(U8), minutes : List(U8), seconds : List(U8), microsecond : U32 }
	definition = |pattern| { hours: pattern.hours, minutes: pattern.minutes, seconds: pattern.seconds, microsecond: pattern.microsecond }

	## At most 86400 candidates. Only the distinct selector fields are stored.
	count : ClockPattern -> U64
	count = |pattern| pattern.hours.len() * pattern.minutes.len() * pattern.seconds.len()
	at : ClockPattern, U64 -> Try(ClockTime, [OutOfRange, ..])
	at = |pattern, index| if index >= count(pattern) {
		Err(OutOfRange)
	} else {
		Ok(candidate(pattern, index))
	}

	## Lazy, infallible traversal of validated candidates. Construction does not
	## allocate their Cartesian product; each advance constructs one clock label.
	iter : ClockPattern -> Iter(ClockTime)
	iter = |pattern| Iter.custom(
		0.U64,
		Known(count(pattern)),
		|index| if index >= count(pattern) {
			Err(NoMore)
		} else {
			Ok((candidate(pattern, index), index + 1))
		},
	)
	to_inspect : ClockPattern -> Str
	to_inspect = |pattern| "ClockPattern(candidates=${count(pattern).to_str()}, microsecond=${pattern.microsecond.to_str()})"
}

normalize = |values, fallback| {
	if values.is_empty() {
		return [fallback]
	}
	sorted = values.sort_with(
		|a, b| if a < b {
			Before
		} else if a > b {
			After
		} else {
			Same
		},
	)
	var $result = []
	var $previous = None
	for value in sorted {
		if $previous != Some(value) {
			$result = $result.append(value)
		}
		$previous = Some(value)
	}
	$result
}

# Constructor invariants: all dimensions nonempty, index < their product,
# fields in ClockTime's domain. Products are <= 86400, arithmetic fits I64.
candidate = |pattern, index| {
	second_index = U64.rem_by(index, pattern.seconds.len())
	minute_index = U64.rem_by(U64.div_trunc_by(index, pattern.seconds.len()), pattern.minutes.len())
	hour_index = U64.div_trunc_by(index, pattern.seconds.len() * pattern.minutes.len())
	hour = field_at(pattern.hours, hour_index)
	minute = field_at(pattern.minutes, minute_index)
	second = field_at(pattern.seconds, second_index)
	match ClockTime.from_fields({ hour, minute, second, microsecond: pattern.microsecond }) {
		Ok(value) => value
		Err(_) => crash "Validated clock-pattern fields"
	}
}

field_at = |values, index| match List.get(values, index) {
	Ok(value) => value
	Err(_) => crash "Clock-pattern dimension index"
}

expect {
	anchor = ClockTime.from_fields({ hour: 12, minute: 10, second: 15, microsecond: 2 })?
	pattern = ClockPattern.new(anchor, { hours: [17, 9, 9], minutes: [30, 0], seconds: [] })?
	var $fields = []
	for clock in pattern {
		$fields = $fields.append(ClockTime.to_fields(clock))
	}
	ClockPattern.count(pattern) == 4 and $fields == [
		{ hour: 9, minute: 0, second: 15, microsecond: 2 },
		{ hour: 9, minute: 30, second: 15, microsecond: 2 },
		{ hour: 17, minute: 0, second: 15, microsecond: 2 },
		{ hour: 17, minute: 30, second: 15, microsecond: 2 },
	] and ClockPattern.at(pattern, 4) == Err(OutOfRange)
}

expect {
	anchor = ClockTime.from_microseconds_since_midnight(0)?
	test_status(anchor, { hours: [24], minutes: [], seconds: [] }) == Err(InvalidHour) and
		test_status(anchor, { hours: [], minutes: [60], seconds: [] }) == Err(InvalidMinute) and
			test_status(anchor, { hours: [], minutes: [], seconds: [60] }) == Err(UnsupportedLeapSecond) and
				test_status(anchor, { hours: [], minutes: [], seconds: [61] }) == Err(InvalidSecond) and
					test_status(anchor, { hours: List.repeat(0, 4097), minutes: [], seconds: [] }) == Err(TooManySelectors)
}

test_status = |anchor, spec| match ClockPattern.new(anchor, spec) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}
