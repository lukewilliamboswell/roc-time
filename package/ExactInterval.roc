import SemanticFact
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
## Parsing accepts at most 513 UTF-8 bytes (two 256-byte timestamp limits
## plus a separator). All construction, conversion and output work is bounded.
## Span projection discards source presentation explicitly; declaration equality
## retains it. Uncertain endpoints and original source spelling are not retained.
## Use canonical text for interchange. See OffsetTimestamp for endpoint limits.
ExactInterval :: { start : OffsetTimestamp, end : OffsetTimestamp, extent : PosixSpan }.{
	## Separates endpoint timestamp errors from malformed interval syntax and empty or reversed resolved bounds.
	Error : [Malformed, Incomplete, TooLarge, Start(OffsetTimestamp.Error), End(OffsetTimestamp.Error), EmptySpan, ReversedBounds]

	## Decode one encoded string using this type's text parser.
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

	## Encodes the canonical standard text as a string in the selected encoding; encoding failures pass through.
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

	## Identifier of the supported text profile described above; it does not imply support for the entire standard.
	profile : Str
	profile = "exact-offset-interval-v1"
	## Constructs a nonempty half-open interval from two timestamp declarations. Rejects equal/reversed resolved boundaries and endpoint range failures.
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
	## Parses two complete offset timestamps separated by one slash. Endpoint errors identify Start or End; this is not a general ISO interval parser.
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
	## Returns the retained start/end declarations, including their fractional widths and offset assertions.
	endpoints : ExactInterval -> { start : OffsetTimestamp, end : OffsetTimestamp }
	endpoints = |value| { start: value.start, end: value.end }
	## Returns the resolved half-open POSIX extent. This projection discards endpoint presentation and offset-assertion distinctions.
	span : ExactInterval -> PosixSpan
	span = |value| value.extent
	## Serializes both retained endpoint declarations, separated by a slash; preserves fractional width and offset intent.
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
	## Compares endpoint declarations as well as their extent. Compare spans when only occupied time matters.
	is_eq : ExactInterval, ExactInterval -> Bool
	is_eq = |a, b| a.start == b.start and a.end == b.end
	## Hashes the same declaration fields used by is_eq, so equal values are interchangeable as dictionary keys.
	to_hash : ExactInterval, Hasher -> Hasher
	to_hash = |value, hasher| value.end.to_hash(value.start.to_hash(hasher))

	## Stored extent plus original endpoint declarations, without re-resolution.
	fact_count : ExactInterval -> U64
	fact_count = |_| 3
	## Returns the zero-based semantic fact, or End when the index is outside fact_count. Facts describe meaning, not a serialized record.
	fact_at : ExactInterval, U64 -> [End, Item(SemanticFact)]
	fact_at = |value, index| {
		if index == 0 {
			return Item(SemanticFact.new(ExactIntervalDescription({ span: value.extent })))
		}
		if index > 2 {
			return End
		}
		endpoint = if index == 1 {
			value.start
		} else {
			value.end
		}
		parts = OffsetTimestamp.parts(endpoint)
		Item(
			SemanticFact.new(
				OffsetEndpoint({
					role: if index == 1 {
						Start
					} else {
						End
					},
					local: OffsetTimestamp.local_label(endpoint),
					fraction_digits: parts.fraction_digits,
					offset: parts.offset,
				}),
			),
		)
	}
	## A concise semantic summary for debugging. Use the standard text encoder for storage or interchange.
	to_inspect : ExactInterval -> Str
	to_inspect = |value| match fact_at(value, 0) {
		Item(fact) => SemanticFact.summary(fact)
		End => crash "ExactInterval always exposes its stored extent at index zero"
	}
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

expect {
	# Source label order is reversed, but explicit offsets establish [0,1h).
	# Facts retain each declaration rather than reconstruct from the UTC span.
	value = ExactInterval.parse("1970-01-01T02:00:00.000+02:00/1970-01-01T01:00:00.000+00:00")?
	span = ExactInterval.span(value)
	first = ExactInterval.endpoints(value).start
	last = ExactInterval.endpoints(value).end
	ExactInterval.fact_count(value) == 3 and
		PosixBoundary.to_microseconds(PosixSpan.start(span)) == 0 and PosixBoundary.to_microseconds(PosixSpan.end(span)) == 3600000000 and
			ExactInterval.fact_at(value, 0) == Item(
				SemanticFact.new(
					ExactIntervalDescription(
						{ span: span },
					),
				),
			) and
				ExactInterval.fact_at(value, 1) == Item(SemanticFact.new(OffsetEndpoint({ role: Start, local: OffsetTimestamp.local_label(first), fraction_digits: 3, offset: OffsetTimestamp.parts(first).offset }))) and
					ExactInterval.fact_at(value, 2) == Item(SemanticFact.new(OffsetEndpoint({ role: End, local: OffsetTimestamp.local_label(last), fraction_digits: 3, offset: OffsetTimestamp.parts(last).offset }))) and
						ExactInterval.fact_at(value, 3) == End and ExactInterval.fact_at(value, U64.highest) == End
}
