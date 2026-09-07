import SemanticFact
import TimedRecurrence
import CalendarPattern
import GregorianDate
import Calendar
import ClockTime
import LocalDateTime
import ZoneRules
import FixedOffset
import PosixSpan
import PosixBoundary
import PosixDelta
import TimedOccurrence

## Positive RFC 5545 duration values for events and PERIOD starts.
## Profile rfc5545-positive-duration-v1 implements section 3.3.6's week,
## day and hour/minute/second grammar, including optional plus and ASCII case.
## Calendar days remain distinct from coordinate seconds; leap seconds are
## not counted. Years, months, fractions, lists and content lines are malformed.
## Negative and zero durations return NonPositive; alarm durations are outside
## this positive profile. Source spelling is not retained.
##
## Parsing visits at most 256 bytes. Days and the coordinate microsecond tail
## must each fit nonnegative I64. Interpretation may still exceed calendar,
## boundary or provider ranges. No rules are consulted during parsing.
##
## ```roc
## import time.ICalDuration
## expect {
##     value = ICalDuration.parse("P15DT5H0M20S")?
##     ICalDuration.components(value) == { days: 15.I64, seconds: 18020.I64 }
## }
## ```
ICalDuration :: { days : I64, seconds : I64 }.{

	## Decode one encoded string using this type's text parser.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : ICalDuration, rest : state }, [InvalidICalDuration(Error), Encoding(err), ..]))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
		]
	parser_for = |encoding| {
		Encoding : encoding
		|state| {
			parsed = match Encoding.parse_str(encoding, state) {
				Ok(value) => value
				Err(error) => return Err(Encoding(error))
			}
			match parse(parsed.value) {
				Ok(value) => Ok({ value, rest: parsed.rest })
				Err(error) => Err(InvalidICalDuration(error))
			}
		}
	}

	## Encodes the canonical standard text as a string in the selected encoding; encoding failures pass through.
	encoder_for : encoding -> (ICalDuration, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(ICalDuration, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid ICalDuration literal: ${Str.inspect(error)}"))
	}

	## Identifier of the supported text profile described above; it does not imply support for the entire standard.
	profile : Str
	profile = "rfc5545-positive-duration-v1"
	## Reports malformed grammar, nonpositive duration, numerical range overflow or the input byte limit.
	Error : [Malformed, NonPositive, OutOfRange, TooLarge]

	## Parses a positive week/day/time duration. Days remain calendar quantities; hours, minutes and seconds form the coordinate tail. No zone is consulted.
	parse : Str -> Try(ICalDuration, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 256 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		var $index = 0.U64
		var $negative = Bool.False
		if bytes.get($index) == Ok(43) or bytes.get($index) == Ok(45) {
			$negative = bytes.get($index) == Ok(45)
			$index = $index + 1
		}
		if upper(bytes.get($index) ?? 0) != 80 {
			return Err(Malformed)
		}
		$index = $index + 1
		var $days = 0.I64
		var $seconds = 0.I128
		var $time = Bool.False
		var $any = Bool.False
		var $time_any = Bool.False
		var $previous = 0.U8
		while $index < bytes.len() {
			if upper(bytes.get($index) ?? 0) == 84 {
				if $time {
					return Err(Malformed)
				}
				$time = Bool.True
				$index = $index + 1
			}
			start = $index
			var $number = 0.I64
			while $index < bytes.len() {
				byte = bytes.get($index) ?? 0
				if byte < 48 or byte > 57 {
					break
				}
				digit = (byte - 48).to_i64()
				if $number > (I64.highest - digit) // 10 {
					return Err(OutOfRange)
				}
				$number = $number * 10 + digit
				$index = $index + 1
			}
			if start == $index {
				return Err(Malformed)
			}
			unit = upper(bytes.get($index) ?? 0)
			$index = $index + 1
			if $time {
				rank = match unit {
					72 => 1.U8
					77 => 2
					83 => 3
					_ => return Err(Malformed)
				}
				# RFC's dur-hour nests dur-minute, which nests dur-second.
				# Thus H followed directly by S is not in this grammar.
				if rank <= $previous or ($previous == 1 and rank == 3) {
					return Err(Malformed)
				}
				$previous = rank
				factor = match rank {
					1 => 3600.I128
					2 => 60
					_ => 1
				}
				$seconds = $seconds + $number.to_i128() * factor
				$time_any = Bool.True
			} else {
				if $any {
					return Err(Malformed)
				}
				match unit {
					87 => {
						if $index != bytes.len() {
							return Err(Malformed)
						}
						if $number > I64.highest // 7 {
							return Err(OutOfRange)
						}
						$days = $number * 7
					}
					68 => {
						$days = $number
					}
					_ => return Err(Malformed)
				}
			}
			$any = Bool.True
		}
		if !$any or ($time and !$time_any) {
			return Err(Malformed)
		}
		if $seconds > I64.highest.to_i128() // 1000000 {
			return Err(OutOfRange)
		}
		if $negative or ($days == 0 and $seconds == 0) {
			return Err(NonPositive)
		}
		tail = match I128.to_i64_try($seconds) {
			Ok(value) => value
			Err(_) => return Err(OutOfRange)
		}
		Ok({ days: $days, seconds: tail })
	}

	## Equality compares nominal days and coordinate seconds, without an anchor.
	is_eq : ICalDuration, ICalDuration -> Bool
	is_eq = |a, b| a.days == b.days and a.seconds == b.seconds
	## Hashes the same declaration fields used by is_eq, so equal values are interchangeable as dictionary keys.
	to_hash : ICalDuration, Hasher -> Hasher
	to_hash = |value, hasher| value.seconds.to_hash(value.days.to_hash(hasher))

	## Returns calendar days and coordinate seconds separately. One day is not replaced by 86400 coordinate seconds.
	components : ICalDuration -> { days : I64, seconds : I64 }
	components = |value| { days: value.days, seconds: value.seconds }

	## Converts to a duration for TimedOccurrence. Days advance the original
	## source before the coordinate tail. The RFC timed policy selects the
	## first fold occurrence and uses the offset before a gap (erratum 4271).
	to_duration : ICalDuration -> TimedOccurrence.Duration
	to_duration = |value| {
		tail = PosixDelta.from_microseconds(value.seconds * 1000000)
		if value.days == 0 {
			Coordinate(tail)
		} else {
			Calendar({ delta: Calendar.Delta.days(value.days), invalid_date: Reject, tail, occurrence: First, gap: UseOffsetBeforeGap })
		}
	}

	## Canonical RFC 5545 duration value text.
	## Weeks become days; accurate time components become seconds.
	to_text : ICalDuration -> Str
	to_text = |value| {
		day = if value.days == 0 {
			""
		} else {
			"${value.days.to_str()}D"
		}
		time = if value.seconds == 0 {
			""
		} else {
			"T${value.seconds.to_str()}S"
		}
		"P${day}${time}"
	}

	## Calendar days and accurate seconds remain separate components, without
	## an invented anchor or conversion of calendar days to elapsed seconds.
	fact_count : ICalDuration -> U64
	fact_count = |_| 1
	## Returns the zero-based semantic fact, or End when the index is outside fact_count. Facts describe meaning, not a serialized record.
	fact_at : ICalDuration, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| if index == 0 {
		Item(SemanticFact.new(ICalDurationDescription({ role: Standalone, days: value.days, seconds: value.seconds })))
	} else {
		End
	}
	## A concise semantic summary for debugging. Use the standard text encoder for storage or interchange.
	to_inspect : ICalDuration -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "RFC duration has a first semantic fact"
	}
}

upper : U8 -> U8
upper = |byte| if byte >= 97 and byte <= 122 {
	byte - 32
} else {
	byte
}

# Independently sourced examples: RFC 5545 section 3.3.6, September 2009.
# https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.6
expect ICalDuration.components(ICalDuration.parse("P15DT5H0M20S")?) == { days: 15.I64, seconds: 18020.I64 }
expect ICalDuration.components(ICalDuration.parse("P7W")?) == { days: 49.I64, seconds: 0.I64 }
expect ICalDuration.to_text(ICalDuration.parse("+p1dt2h3m4s")?) == "P1DT7384S"
expect {
	var $valid = Bool.True
	for text in ["", "P", "PT", "P1DT", "P1W1D", "P1WT1H", "PT1H1S", "PT1M1H", "PT1S1S", "P1D1D", "P1Y", "P1M", "PT1.5S", "P1D ", "P1DT1HT1M"] {
		$valid = $valid and ICalDuration.parse(text) == Err(Malformed)
	}
	$valid
}
expect ICalDuration.parse("-PT1S") == Err(NonPositive)
expect ICalDuration.parse("P0D") == Err(NonPositive)
expect ICalDuration.parse("PT9223372036855S") == Err(OutOfRange)
expect ICalDuration.parse("P9223372036854775808D") == Err(OutOfRange)
expect ICalDuration.parse("P1317624576693539402W") == Err(OutOfRange)
expect ICalDuration.components(ICalDuration.parse("PT9223372036854S")?).seconds == 9223372036854
expect ICalDuration.components(ICalDuration.parse("P9223372036854775807D")?).days == I64.highest
expect ICalDuration.parse("P${"0".repeat(256)}D") == Err(TooLarge)

# R11/R12: independent piecewise offset model: [0,12h) has offset zero,
# [12h,3d) has offset +1h. The next local midnight is therefore at 23h.
# This distinguishes RFC nominal days from accurate hours without relying on
# parser/formatter agreement or another recurrence engine.
expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	source = LocalDateTime.new(Calendar.Date.from_gregorian(date), clock)
	end_date = GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?
	end = LocalDateTime.new(Calendar.Date.from_gregorian(end_date), clock)
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(259200000000))?
	rules = ZoneRules.new_bounded("Synthetic/Duration", "v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(43200000000), offset: FixedOffset.from_seconds(3600) }], { minimum: 0, maximum: 3600 })?
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	cursor = TimedRecurrence.cursor(rule, { start: source, end }, { rules, occurrence: First, gap: UseOffsetBeforeGap })?
	batch = TimedRecurrence.Cursor.next(cursor, { max_steps: 10, max_buffered: 1, max_zone_segments: 2, max_zone_candidates: 1 })?
	start = match batch.status {
		Item(item) => item.occurrence
		_ => crash "fixture start"
	}
	var $valid = Bool.True
	for case in [{ text: "P1D", hours: 23.I64 }, { text: "PT24H", hours: 24 }, { text: "P1DT1H", hours: 24 }] {
		parsed = ICalDuration.parse(case.text)?
		pending = TimedOccurrence.cursor({}, start, ICalDuration.to_duration(parsed))?
		paused = TimedOccurrence.Cursor.collect(pending, { max_segments: 0, max_candidates: 1 })?
		result = match paused.status {
			Complete(value) => value
			Limited(progress) => {
				resumed = TimedOccurrence.Cursor.collect(progress.cursor, { max_segments: 2, max_candidates: 1 })?
				match resumed.status {
					Complete(value) => value
					Limited(_) => crash "fixture end"
				}
			}
		}
		$valid = $valid and PosixSpan.coordinate_width(TimedOccurrence.span(result)) == Ok(PosixDelta.from_microseconds(case.hours * 3600000000))
	}
	$valid and ICalDuration.parse("P1D") != ICalDuration.parse("PT24H")
}

expect {
	day = ICalDuration.parse("P1D")?
	hours = ICalDuration.parse("PT24H")?
	huge = ICalDuration.parse("P9223372036854775807D")?
	ICalDuration.fact_at(day, 0) == Item(SemanticFact.new(ICalDurationDescription({ role: Standalone, days: 1, seconds: 0 }))) and
		ICalDuration.fact_at(hours, 0) == Item(SemanticFact.new(ICalDurationDescription({ role: Standalone, days: 0, seconds: 86400 }))) and
			ICalDuration.fact_at(huge, 0) == Item(SemanticFact.new(ICalDurationDescription({ role: Standalone, days: I64.highest, seconds: 0 }))) and
				ICalDuration.fact_count(huge) == 1 and ICalDuration.fact_at(huge, 1) == End and
					ICalDuration.fact_at(huge, U64.highest) == End and ICalDuration.to_inspect(huge).count_utf8_bytes() <= 256
}
