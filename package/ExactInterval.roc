import OffsetTimestamp
import PosixSpan
import PosixBoundary

## Exact appointments, native profile exact-offset-interval-v1. Both endpoints
## are complete OffsetTimestamp declarations, separated by one slash. The start
## is inclusive and the end exclusive, with start strictly before end after
## resolving each supplied offset. Canonical text retains endpoint declarations,
## including fractional width and asserted versus unasserted offsets.
##
## RFC 3339 does not specify interval syntax: this composition is a native
## contract, not an ISO/EDTF conformance claim. Bare dates, durations, abbreviated
## or missing endpoints and annotations are unsupported by this exact profile.
## Date-only EDTF endpoints mean something different and are never inferred here.
##
## Parsing checks 513 UTF-8 bytes before copying (two 256-byte timestamp limits
## plus a separator). All construction, conversion and output work is bounded.
## Span projection discards source presentation explicitly; declaration equality
## retains it. No uncertain-endpoint interpretation, source fidelity or versioned
## persistence claim is made. See OffsetTimestamp for its RFC source contracts.
ExactInterval :: { start : OffsetTimestamp, end : OffsetTimestamp, extent : PosixSpan }.{
	Error : [Malformed, Incomplete, TooLarge, Start(OffsetTimestamp.Error), End(OffsetTimestamp.Error), EmptySpan, ReversedBounds]

	## Generic encodings carry canonical text, never the opaque backing record.
	## Encoding failures remain distinct from this profile's validation errors.
	## The encoding owns framing and its work limits; parse bounds the decoded text.
	parser_for : encoding -> (state -> Try({ value : ExactInterval, rest : state }, [InvalidExactInterval(Error), Encoding(err), ..]))
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
				Err(error) => Err(InvalidExactInterval(error))
			}
		}
	}

	encoder_for : encoding -> (ExactInterval, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding
		|value, state| Encoding.encode_str(to_text(value), state)
	}

	## Typed quoted literals use the same checked profile at compile time.
	## Runtime interpolation remains Str followed by an explicit parse call.
	from_quote : Str -> Try(ExactInterval, [BadQuotedBytes(Str)])
	from_quote = |text| match parse(text) {
		Ok(value) => Ok(value)
		Err(error) => Err(BadQuotedBytes("Invalid ExactInterval literal: ${Str.inspect(error)}"))
	}

	profile : Str
	profile = "exact-offset-interval-v1"
	new : OffsetTimestamp, OffsetTimestamp -> Try(ExactInterval, Error)
	new = |start, end| {
		low = match OffsetTimestamp.boundary(start) {
			Ok(value) => value
			Err(_) => return Err(Start(OutOfRange))
		}
		high = match OffsetTimestamp.boundary(end) {
			Ok(value) => value
			Err(_) => return Err(End(OutOfRange))
		}
		extent = match PosixSpan.new(low, high) {
			Ok(value) => value
			Err(EmptySpan) => return Err(EmptySpan)
			Err(ReversedBounds) => return Err(ReversedBounds)
		}
		Ok({ start, end, extent })
	}
	parse : Str -> Try(ExactInterval, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 513 {
			return Err(TooLarge)
		}
		parts = text.split_on("/")
		if parts.len() > 2 {
			return Err(Malformed)
		}
		start_text = parts.first() ?? ""
		start = match OffsetTimestamp.parse(start_text) {
			Ok(value) => value
			Err(error) => return Err(Start(error))
		}
		if parts.len() < 2 {
			return Err(Incomplete)
		}
		end_text = parts.get(1) ?? ""
		end = match OffsetTimestamp.parse(end_text) {
			Ok(value) => value
			Err(error) => return Err(End(error))
		}
		new(start, end)
	}
	endpoints : ExactInterval -> { start : OffsetTimestamp, end : OffsetTimestamp }
	endpoints = |value| { start: value.start, end: value.end }
	span : ExactInterval -> PosixSpan
	span = |value| value.extent
	to_text : ExactInterval -> Str
	to_text = |value| "${OffsetTimestamp.to_text(value.start)}/${OffsetTimestamp.to_text(value.end)}"

	## Explicit offset and exact fractional width for computed coverage output.
	## Precision loss fails; output never silently rounds a boundary.
	from_span : PosixSpan, OffsetTimestamp.Offset, U8 -> Try(ExactInterval, Error)
	from_span = |extent, offset, fraction_digits| {
		start = match OffsetTimestamp.from_boundary(PosixSpan.start(extent), offset, fraction_digits) {
			Ok(value) => value
			Err(error) => return Err(Start(error))
		}
		end = match OffsetTimestamp.from_boundary(PosixSpan.end(extent), offset, fraction_digits) {
			Ok(value) => value
			Err(error) => return Err(End(error))
		}
		new(start, end)
	}
	is_eq : ExactInterval, ExactInterval -> Bool
	is_eq = |a, b| a.start == b.start and a.end == b.end
	to_hash : ExactInterval, Hasher -> Hasher
	to_hash = |value, hasher| value.end.to_hash(value.start.to_hash(hasher))
	to_inspect : ExactInterval -> Str
	to_inspect = |value| "ExactInterval(${to_text(value)})"
}

# Independent epoch-relative model: each positive hour is 3600000000
# microseconds; subtract the explicit local offset before comparing endpoints.
expect {
	a = ExactInterval.parse("1970-01-01T01:00:00+01:00/1970-01-01T03:00:00+02:00")?
	PosixBoundary.to_microseconds(PosixSpan.start(ExactInterval.span(a))) == 0 and PosixBoundary.to_microseconds(PosixSpan.end(ExactInterval.span(a))) == 3600000000
}
expect {
	a = ExactInterval.parse("1970-01-01T00:00:00Z/1970-01-01T01:00:00Z")?
	b = ExactInterval.parse("1970-01-01T02:00:00+01:00/1970-01-01T03:00:00+01:00")?
	PosixSpan.end(ExactInterval.span(a)) == PosixSpan.start(ExactInterval.span(b)) and
		ExactInterval.parse("1970-01-01T01:00:00+01:00/1970-01-01T00:00:00Z") == Err(EmptySpan) and
			ExactInterval.parse("1970-01-01T00:00:00Z/1970-01-01T01:00:00+02:00") == Err(ReversedBounds)
}
expect {
	a = ExactInterval.parse("1969-12-31t23:59:59.999999z/1970-01-01T00:00:00.000000-00:00")?
	ExactInterval.to_text(a) == "1969-12-31T23:59:59.999999Z/1970-01-01T00:00:00.000000Z" and
		PosixBoundary.to_microseconds(PosixSpan.start(ExactInterval.span(a))) == -1 and PosixBoundary.to_microseconds(PosixSpan.end(ExactInterval.span(a))) == 0
}
expect {
	a = ExactInterval.parse("1970-01-01T00:00:00.12Z/1970-01-01T00:00:00.13Z")?
	b = ExactInterval.parse("1970-01-01T00:00:00.120Z/1970-01-01T00:00:00.130Z")?
	a != b and ExactInterval.span(a) == ExactInterval.span(b) and ExactInterval.from_span(ExactInterval.span(b), UnassertedUtc, 2) == Ok(a) and ExactInterval.from_span(ExactInterval.span(b), UnassertedUtc, 1) == Err(Start(UnsupportedPrecision))
}
expect {
	ExactInterval.parse("1964/2008") == Err(Start(Incomplete)) and
		ExactInterval.parse("1970-01-01T00:00:00Z/") == Err(End(Incomplete)) and
			ExactInterval.parse("/1970-01-01T00:00:00Z") == Err(Start(Incomplete)) and
				ExactInterval.parse("1970-01-01T00:00:00Z") == Err(Incomplete) and
					ExactInterval.parse("1970-01-01T00:00:00Z/P1D") == Err(End(Malformed)) and
						ExactInterval.parse("1970-01-01T00:00:00Z/..") == Err(End(Malformed)) and
							ExactInterval.parse("a/b/c") == Err(Malformed) and
								ExactInterval.parse("x".repeat(514)) == Err(TooLarge)
}
