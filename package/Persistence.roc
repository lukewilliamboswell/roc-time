import PersistenceEnvelope
import EdtfDate
import OffsetTimestamp
import ExactInterval
import Ixdtf
import RfcDateTime
import RfcDuration
import RfcPeriod
import PosixBoundary
import PosixDelta

## Version 1 native persistence for seven supported text declarations and exact
## POSIX boundary/displacement values. The JSON envelope has seven required
## string fields: format, version, kind, profile, axis, unit and payload.
## Format is roc-time; version is 1. Unknown metadata errors before temporal
## payload interpretation. No private records or compiler union encoding leak.
##
## Text declarations use their declared canonical semantic text/profile and
## axis/unit none: they are source declarations, not resolved snapshots. This
## preserves resolution, qualifiers, UTC/local forms and ordered annotations;
## original spelling is not preserved. Decode never fetches context or resolves
## zones. Snapshot/rule/event/coverage/calendar-native persistence is outside
## this initial profile and unsupported kinds fail explicitly.
##
## Core kinds posix-boundary and posix-delta use profile posix-microseconds-v1,
## axis posix-1970, unit microsecond. Their payload is a canonical signed decimal
## STRING, including either I64 limit: no JSON floating-point precision loss.
## A delta is coordinate displacement, not physical elapsed SI time.
##
## Envelope decoding is bounded to 65536 encoded bytes and seven string fields.
## This type's canonical outputs fit below 8192 bytes: the largest payload is
## Ixdtf's bounded 4096-byte ASCII declaration; metadata is fixed and small.
## Encoding does not interpret descriptions or enumerate temporal domains.
## Generic parser_for/encoder_for hooks are intentionally unsupported: use
## parse/to_text for the versioned envelope. Generic JSON must not derive the
## private Value representation or mistake it for this persistence contract.
Persistence :: { stored : Value }.{
	Value : [EdtfDate(EdtfDate), OffsetTimestamp(OffsetTimestamp), ExactInterval(ExactInterval), Ixdtf(Ixdtf), RfcDateTime(RfcDateTime), RfcDuration(RfcDuration), RfcPeriod(RfcPeriod), PosixBoundary(PosixBoundary), PosixDelta(PosixDelta)]
	Error : [Envelope(PersistenceEnvelope.Error), UnknownFormat(Str), UnknownVersion(Str), UnknownKind(Str), UnsupportedProfile(Str), UnsupportedAxis(Str), UnsupportedUnit(Str), InvalidEdtfDate(EdtfDate.Error), InvalidOffsetTimestamp(OffsetTimestamp.Error), InvalidExactInterval(ExactInterval.Error), InvalidIxdtf(Ixdtf.Error), InvalidRfcDateTime(RfcDateTime.Error), InvalidRfcDuration(RfcDuration.Error), InvalidRfcPeriod(RfcPeriod.Error), InvalidInteger, OutOfRange]
	new : Value -> Persistence
	new = |stored| { stored: stored }
	value : Persistence -> Value
	value = |wrapped| wrapped.stored

	parse : Str -> Try(Persistence, Error)
	parse = |text| {
		envelope = match PersistenceEnvelope.parse(text) {
			Ok(inner) => inner
			Err(error) => return Err(Envelope(error))
		}
		fields = PersistenceEnvelope.fields(envelope)
		if fields.format != "roc-time" {
			return Err(UnknownFormat(fields.format))
		}
		if fields.version != "1" {
			return Err(UnknownVersion(fields.version))
		}
		expected = match metadata(fields.kind) {
			None => return Err(UnknownKind(fields.kind))
			Some(inner) => inner
		}
		if fields.profile != expected.profile {
			return Err(UnsupportedProfile(fields.profile))
		}
		if fields.axis != expected.axis {
			return Err(UnsupportedAxis(fields.axis))
		}
		if fields.unit != expected.unit {
			return Err(UnsupportedUnit(fields.unit))
		}
		stored = match fields.kind {
			"edtf-date" => match EdtfDate.parse(fields.payload) {
				Ok(inner) => EdtfDate(inner)
				Err(error) => return Err(InvalidEdtfDate(error))
			}
			"offset-timestamp" => match OffsetTimestamp.parse(fields.payload) {
				Ok(inner) => OffsetTimestamp(inner)
				Err(error) => return Err(InvalidOffsetTimestamp(error))
			}
			"exact-interval" => match ExactInterval.parse(fields.payload) {
				Ok(inner) => ExactInterval(inner)
				Err(error) => return Err(InvalidExactInterval(error))
			}
			"ixdtf" => match Ixdtf.parse(fields.payload) {
				Ok(inner) => Ixdtf(inner)
				Err(error) => return Err(InvalidIxdtf(error))
			}
			"rfc-date-time" => match RfcDateTime.parse(fields.payload) {
				Ok(inner) => RfcDateTime(inner)
				Err(error) => return Err(InvalidRfcDateTime(error))
			}
			"rfc-duration" => match RfcDuration.parse(fields.payload) {
				Ok(inner) => RfcDuration(inner)
				Err(error) => return Err(InvalidRfcDuration(error))
			}
			"rfc-period" => match RfcPeriod.parse(fields.payload) {
				Ok(inner) => RfcPeriod(inner)
				Err(error) => return Err(InvalidRfcPeriod(error))
			}
			"posix-boundary" => PosixBoundary(PosixBoundary.from_microseconds(integer(fields.payload)?))
			"posix-delta" => PosixDelta(PosixDelta.from_microseconds(integer(fields.payload)?))
			_ => return Err(UnknownKind(fields.kind))
		}
		Ok(new(stored))
	}

	to_text : Persistence -> Str
	to_text = |wrapped| {
		{ kind, payload } = match wrapped.stored {
			EdtfDate(inner) => { kind: "edtf-date", payload: EdtfDate.to_text(inner) }
			OffsetTimestamp(inner) => { kind: "offset-timestamp", payload: OffsetTimestamp.to_text(inner) }
			ExactInterval(inner) => { kind: "exact-interval", payload: ExactInterval.to_text(inner) }
			Ixdtf(inner) => { kind: "ixdtf", payload: Ixdtf.to_text(inner) }
			RfcDateTime(inner) => { kind: "rfc-date-time", payload: RfcDateTime.to_text(inner) }
			RfcDuration(inner) => { kind: "rfc-duration", payload: RfcDuration.to_text(inner) }
			RfcPeriod(inner) => { kind: "rfc-period", payload: RfcPeriod.to_text(inner) }
			PosixBoundary(inner) => { kind: "posix-boundary", payload: PosixBoundary.to_microseconds(inner).to_str() }
			PosixDelta(inner) => { kind: "posix-delta", payload: PosixDelta.to_microseconds(inner).to_str() }
		}
		description = match metadata(kind) {
			Some(inner) => inner
			None => crash "Every persistent Value has declared metadata"
		}
		# The largest payload is 4096 bytes. Even maximal six-byte JSON
		# escaping plus fixed metadata fits well inside the envelope's 64KiB cap.
		Json.to_str({ format: "roc-time", version: "1", kind, profile: description.profile, axis: description.axis, unit: description.unit, payload })
	}

	is_eq : Persistence, Persistence -> Bool
	is_eq = |a, b| a.stored == b.stored
	to_hash : Persistence, Hasher -> Hasher
	to_hash = |wrapped, hasher| match wrapped.stored {
		EdtfDate(inner) => inner.to_hash((0.U8).to_hash(hasher))
		OffsetTimestamp(inner) => inner.to_hash((1.U8).to_hash(hasher))
		ExactInterval(inner) => inner.to_hash((2.U8).to_hash(hasher))
		Ixdtf(inner) => inner.to_hash((3.U8).to_hash(hasher))
		RfcDateTime(inner) => inner.to_hash((4.U8).to_hash(hasher))
		RfcDuration(inner) => inner.to_hash((5.U8).to_hash(hasher))
		RfcPeriod(inner) => inner.to_hash((6.U8).to_hash(hasher))
		PosixBoundary(inner) => inner.to_hash((7.U8).to_hash(hasher))
		PosixDelta(inner) => inner.to_hash((8.U8).to_hash(hasher))
	}
	to_inspect : Persistence -> Str
	to_inspect = |wrapped| {
		kind = match wrapped.stored {
			EdtfDate(_) => "edtf-date"
			OffsetTimestamp(_) => "offset-timestamp"
			ExactInterval(_) => "exact-interval"
			Ixdtf(_) => "ixdtf"
			RfcDateTime(_) => "rfc-date-time"
			RfcDuration(_) => "rfc-duration"
			RfcPeriod(_) => "rfc-period"
			PosixBoundary(_) => "posix-boundary"
			PosixDelta(_) => "posix-delta"
		}
		"Persistence(version=1, kind=${kind})"
	}
}

metadata = |kind| {
	profile = match kind {
		"edtf-date" => EdtfDate.profile
		"offset-timestamp" => OffsetTimestamp.profile
		"exact-interval" => ExactInterval.profile
		"ixdtf" => Ixdtf.profile
		"rfc-date-time" => RfcDateTime.profile
		"rfc-duration" => RfcDuration.profile
		"rfc-period" => RfcPeriod.profile
		"posix-boundary" => "posix-microseconds-v1"
		"posix-delta" => "posix-microseconds-v1"
		_ => return None
	}
	core = kind == "posix-boundary" or kind == "posix-delta"
	Some({
		profile,
		axis: if core {
			"posix-1970"
		} else {
			"none"
		},
		unit: if core {
			"microsecond"
		} else {
			"none"
		},
	})
}

# Canonical decimal strings avoid relying on JSON consumers' numeric range.
# Validate syntax before checked conversion so overflow is distinct from spelling.
integer : Str -> Try(I64, [InvalidInteger, OutOfRange, ..])
integer = |text| {
	bytes = text.to_utf8()
	if bytes.is_empty() {
		return Err(InvalidInteger)
	}
	negative = bytes.first() == Ok(45)
	start = if negative {
		1.U64
	} else {
		0
	}
	if bytes.len() == start {
		return Err(InvalidInteger)
	}
	first = match bytes.get(start) {
		Ok(value) => value
		Err(_) => crash "Nonempty decimal magnitude validated"
	}
	if first == 48 and (negative or bytes.len() > start + 1) {
		return Err(InvalidInteger)
	}
	for byte in bytes.drop_first(start) {
		if byte < 48 or byte > 57 {
			return Err(InvalidInteger)
		}
	}
	match I64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

expect {
	# Independent exact JSON fixture: these digits exceed IEEE754's exact
	# integer range and must remain quoted rather than pass through a float.
	text = "{\"format\":\"roc-time\",\"version\":\"1\",\"kind\":\"posix-boundary\",\"profile\":\"posix-microseconds-v1\",\"axis\":\"posix-1970\",\"unit\":\"microsecond\",\"payload\":\"9007199254740993\"}"
	value = Persistence.parse(text)?
	Persistence.value(value) == PosixBoundary(PosixBoundary.from_microseconds(9007199254740993)) and
		Persistence.parse(Persistence.to_text(value)) == Ok(value)
}
expect {
	var valid = Bool.True
	for number in [I64.lowest, -1, 0, 9007199254740993, I64.highest] {
		boundary = Persistence.new(PosixBoundary(PosixBoundary.from_microseconds(number)))
		delta = Persistence.new(PosixDelta(PosixDelta.from_microseconds(number)))
		valid = valid and boundary != delta and Persistence.parse(Persistence.to_text(boundary)) == Ok(boundary) and Persistence.parse(Persistence.to_text(delta)) == Ok(delta)
	}
	valid
}
expect {
	integer("9223372036854775808") == Err(OutOfRange) and integer("-9223372036854775809") == Err(OutOfRange) and
		integer("-0") == Err(InvalidInteger) and integer("00") == Err(InvalidInteger) and integer("+1") == Err(InvalidInteger) and
			integer("1e3") == Err(InvalidInteger) and integer("1.0") == Err(InvalidInteger) and integer(" 1") == Err(InvalidInteger)
}
expect {
	var valid = Bool.True
	for stored in [
		EdtfDate(EdtfDate.parse("1984?")?),
		OffsetTimestamp(OffsetTimestamp.parse("2000-01-01T00:00:00.120+00:00")?),
		ExactInterval(ExactInterval.parse("2000-01-01T00:00:00Z/2000-01-02T00:00:00Z")?),
		Ixdtf(Ixdtf.parse("2000-01-01T00:00:00Z[u-ca=hebrew][knort=blargel]")?),
		RfcDateTime(RfcDateTime.parse("20000101T000000")?),
		RfcDuration(RfcDuration.parse("P1DT1H")?),
		RfcPeriod(RfcPeriod.parse("20000101T000000/P1D")?),
	] {
		value = Persistence.new(stored)
		valid = valid and Persistence.parse(Persistence.to_text(value)) == Ok(value)
	}
	valid
}
expect {
	base = { format: "roc-time", version: "1", kind: "edtf-date", profile: EdtfDate.profile, axis: "none", unit: "none", payload: "not a date" }
	test_parse({ ..base, format: "other" }) == Err(UnknownFormat("other")) and
		test_parse({ ..base, version: "2" }) == Err(UnknownVersion("2")) and
			test_parse({ ..base, kind: "ixdtf-snapshot" }) == Err(UnknownKind("ixdtf-snapshot")) and
				test_parse({ ..base, profile: "other" }) == Err(UnsupportedProfile("other")) and
					test_parse({ ..base, axis: "posix-1970" }) == Err(UnsupportedAxis("posix-1970")) and
						test_parse({ ..base, unit: "microsecond" }) == Err(UnsupportedUnit("microsecond")) and
							test_parse(base) == Err(InvalidEdtfDate(Malformed))
}

test_parse = |fields| {
	envelope = match PersistenceEnvelope.new(fields) {
		Ok(value) => value
		Err(_) => crash "Small metadata fixture fits envelope"
	}
	Persistence.parse(PersistenceEnvelope.to_text(envelope))
}

expect {
	boundary = Persistence.new(PosixBoundary(PosixBoundary.from_microseconds(1)))
	replay = Persistence.parse(Persistence.to_text(boundary))?
	delta = Persistence.new(PosixDelta(PosixDelta.from_microseconds(1)))
	dictionary = Dict.insert(Dict.insert(Dict.empty(), boundary, "position"), delta, "displacement")
	Dict.get(dictionary, replay) == Ok("position") and Dict.get(dictionary, delta) == Ok("displacement") and
		Str.inspect(boundary) == "Persistence(version=1, kind=posix-boundary)"
}
