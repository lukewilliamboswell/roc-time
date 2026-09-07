import Ixdtf
import ZoneRules
import FixedOffset
import PosixBoundary
import PosixSpan
import PersistenceEnvelope
import PersistenceFields
import PersistenceRules

## Full immutable IXDTF interpretation, ixdtf-strict-snapshot-v1. The payload is
## a flat JSON array of strings: policy, source, stored boundary, stored offset,
## context marker; optional complete rule definition follows. Rules preserve
## exact microsecond validity/transitions, global offset bounds and provenance.
## Decoding reuses ZoneRules.from_definition and Ixdtf.resolve, then checks the
## stored boundary and offset. It never substitutes the host's current database.
## Unsupported presentation preferences remain attached to the known instant.
##
## Policy is strict-v1. None context has five fields. Rules context has eighteen
## header fields in this order: policy, source, stored boundary, stored offset,
## context, name, version, validity start, validity end, initial offset, minimum
## offset, maximum offset, provenance marker, requested name, canonical name,
## source digest, provenance profile, transition count. Transition pairs follow.
## Boundaries are signed I64 POSIX microseconds since 1970; offsets and bounds
## are signed I32 seconds; the count is a nonnegative canonical decimal integer.
## Validity is half-open. Supplied
## provenance uses four empty reserved strings; database provenance fills them.
## All integers use canonical decimal spelling. Maximum 1024 transitions,
## 4096 combined rule metadata bytes, 2066 string fields and 49152 payload bytes.
## The complete outer envelope is also checked against its 65536-byte limit.
## Size checks precede transition formatting; JSON syntax uses builtin hooks.
## The helper caches canonical payload text after validation.
PersistenceSnapshot :: { bound : Ixdtf.Snapshot, text : Str }.{
	RulesError : PersistenceRules.RulesError
	Error : [TooLarge, Malformed, TooManyTransitions, UnsupportedPolicy, InvalidInteger, OutOfRange, InvalidSource(Ixdtf.Error), InvalidRules(RulesError), InvalidBounds([EmptySpan, ReversedBounds]), InvalidSnapshot(Ixdtf.ResolveError), StoredMismatch]
	from_snapshot : Ixdtf.Snapshot -> Try(PersistenceSnapshot, [TooLarge, ..])
	from_snapshot = |bound| {
		context = Ixdtf.Snapshot.context(bound)
		match context {
			None => {}
			Some(rules) => {
				if !PersistenceRules.fits(rules) {
					return Err(TooLarge)
				}
			}
		}
		var $fields = ["strict-v1", Ixdtf.to_text(Ixdtf.Snapshot.source(bound)), PosixBoundary.to_microseconds(Ixdtf.Snapshot.boundary(bound)).to_str(), FixedOffset.to_seconds(Ixdtf.Snapshot.offset(bound)).to_str()]
		match context {
			None => {
				$fields = $fields.append("none")
			}
			Some(rules) => {
				$fields = $fields.append("rules").concat(PersistenceRules.to_fields(rules))
			}
		}
		text = Json.to_str($fields)
		if text.count_utf8_bytes() > 49152 {
			return Err(TooLarge)
		}
		match PersistenceEnvelope.new({ format: "roc-time", version: "1", kind: "ixdtf-snapshot", profile: "ixdtf-strict-snapshot-v1", axis: "posix-1970", unit: "microsecond", payload: text }) {
			Ok(_) => Ok({ bound, text })
			Err(_) => Err(TooLarge)
		}
	}
	snapshot : PersistenceSnapshot -> Ixdtf.Snapshot
	snapshot = |value| value.bound
	to_text : PersistenceSnapshot -> Str
	to_text = |value| value.text
	is_eq : PersistenceSnapshot, PersistenceSnapshot -> Bool
	is_eq = |a, b| a.text == b.text
	to_hash : PersistenceSnapshot, Hasher -> Hasher
	to_hash = |value, hasher| value.text.to_hash(hasher)
	parse : Str -> Try(PersistenceSnapshot, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 49152 {
			return Err(TooLarge)
		}
		decoded : Try(Fields, [InvalidJson(Str), Encoding([InvalidJson(Str)]), TooManyFields, UnsupportedContainer])
		decoded = Json.parse(text)
		fields = match decoded {
			Ok(value) => Fields.values(value)
			Err(TooManyFields) => return Err(TooManyTransitions)
			Err(_) => return Err(Malformed)
		}
		if fields.len() < 5 {
			return Err(Malformed)
		}
		if at(fields, 0) != "strict-v1" {
			return Err(UnsupportedPolicy)
		}
		source = match Ixdtf.parse(at(fields, 1)) {
			Ok(value) => value
			Err(error) => return Err(InvalidSource(error))
		}
		boundary = integer(at(fields, 2))?
		offset = offset_integer(at(fields, 3))?
		context = match at(fields, 4) {
			"none" => {
				if fields.len() != 5 {
					return Err(Malformed)
				}
				None
			}
			"rules" => {
				rules = match PersistenceRules.from_fields(fields.sublist({ start: 5, len: fields.len() - 5 })) {
					Ok(value) => value
					Err(TooLarge) => return Err(TooLarge)
					Err(Malformed) => return Err(Malformed)
					Err(TooManyTransitions) => return Err(TooManyTransitions)
					Err(InvalidInteger) => return Err(InvalidInteger)
					Err(OutOfRange) => return Err(OutOfRange)
					Err(InvalidRules(error)) => return Err(InvalidRules(error))
					Err(InvalidBounds(error)) => return Err(InvalidBounds(error))
				}
				Some(rules)
			}
			_ => return Err(Malformed)
		}
		bound = match Ixdtf.resolve(source, context) {
			Ok(value) => value
			Err(error) => return Err(InvalidSnapshot(error))
		}
		if PosixBoundary.to_microseconds(Ixdtf.Snapshot.boundary(bound)) != boundary or FixedOffset.to_seconds(Ixdtf.Snapshot.offset(bound)) != offset {
			return Err(StoredMismatch)
		}
		match from_snapshot(bound) {
			Ok(value) => Ok(value)
			Err(_) => Err(TooLarge)
		}
	}
	Fields :: { values : List(Str) }.{
		values : Fields -> List(Str)
		values = |fields| fields.values
		parser_for : encoding -> (state -> Try({ value : Fields, rest : state }, [Encoding(err), TooManyFields, UnsupportedContainer, ..]))
			where [
				encoding.parse_list_start : encoding, state -> Try([Counted({ len : U64, rest : state }), Uncounted(state)], err),
				encoding.parse_list_next : encoding, state -> Try([Item(state), Done(state)], err),
				encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
				encoding.parse_list_after_item : encoding, state -> Try([Continue(state), Done(state)], err),
			]
		parser_for = |encoding| {
			parse_fields = PersistenceFields.parser(encoding, 2066)
			|state| {
				parsed = parse_fields(state)?
				Ok({ value: { values: parsed.value }, rest: parsed.rest })
			}
		}

	}
}

integer : Str -> Try(I64, PersistenceSnapshot.Error)
integer = |text| match PersistenceRules.integer(text) {
	Ok(value) => Ok(value)
	Err(OutOfRange) => Err(OutOfRange)
	Err(_) => Err(InvalidInteger)
}

offset_integer : Str -> Try(I32, PersistenceSnapshot.Error)
offset_integer = |text| match PersistenceRules.offset_integer(text) {
	Ok(value) => Ok(value)
	Err(OutOfRange) => Err(OutOfRange)
	Err(_) => Err(InvalidInteger)
}

at = |values, index| match values.get(index) {
	Ok(value) => value
	Err(_) => crash "Snapshot header length and transition pair arity validated"
}

# Independently specified zero instant with an unsupported preferred calendar.
# Interpretation completeness does not imply presentation support.
expect {
	source = Ixdtf.parse("1970-01-01T00:00:00Z[u-ca=hebrew]")?
	bound = Ixdtf.resolve(source, None)?
	value = PersistenceSnapshot.from_snapshot(bound)?
	restored = PersistenceSnapshot.parse(PersistenceSnapshot.to_text(value))?
	PersistenceSnapshot.to_text(value) == Json.to_str(["strict-v1", "1970-01-01T00:00:00Z[u-ca=hebrew]", "0", "0", "none"]) and
		Ixdtf.Snapshot.boundary(PersistenceSnapshot.snapshot(restored)) == PosixBoundary.from_microseconds(0) and
			Ixdtf.Snapshot.presentation(PersistenceSnapshot.snapshot(restored)) == Err(UnsupportedCalendar("hebrew")) and value == restored
}
expect {
	value = fixture("Fixture/Alias", "v\"\\\n😀", True)?
	restored = PersistenceSnapshot.parse(PersistenceSnapshot.to_text(value))?
	rules = match Ixdtf.Snapshot.context(PersistenceSnapshot.snapshot(restored)) {
		Some(v) => v
		None => crash "Fixture snapshot retains supplied rules"
	}
	data = ZoneRules.definition(rules)
	value == restored and data.name == "Fixture/Canonical" and data.version == "v\"\\\n😀" and data.provenance == DatabaseSource({ requested_name: "Fixture/Alias", canonical_name: "Fixture/Canonical", source_digest: "digest\"\\\n😀", profile: "fixture-v1" }) and data.bounds == { minimum: 0, maximum: 3600 } and data.transitions.len() == 2
}
expect {
	value = fixture("Fixture/Canonical", "microseconds", False)?
	fields = parts(PersistenceSnapshot.to_text(value))?
	restored = PersistenceSnapshot.parse(PersistenceSnapshot.to_text(value))?
	rules = match Ixdtf.Snapshot.context(PersistenceSnapshot.snapshot(restored)) {
		Some(v) => v
		None => crash "Fixture snapshot retains supplied rules"
	}
	definition = ZoneRules.definition(rules)
	PersistenceSnapshot.to_text(value) == Json.to_str(["strict-v1", "1970-01-01T00:00:00Z[Fixture/Canonical][u-ca=hebrew]", "0", "0", "rules", "Fixture/Canonical", "microseconds", "-10", "10", "0", "0", "3600", "supplied", "", "", "", "", "2", "-5", "0", "5", "3600"]) and
		at(fields, 18) == "-5" and at(fields, 20) == "5" and PosixBoundary.to_microseconds(PosixSpan.start(definition.validity)) == -10 and PosixBoundary.to_microseconds(PosixSpan.end(definition.validity)) == 10 and value == restored
}
expect {
	value = fixture("Fixture/Canonical", "strict", False)?
	fields = parts(PersistenceSnapshot.to_text(value))?
	PersistenceSnapshot.parse(changed(fields, 0, "future-policy")) == Err(UnsupportedPolicy) and
		PersistenceSnapshot.parse(changed(fields, 2, "1")) == Err(StoredMismatch) and
			PersistenceSnapshot.parse(changed(fields, 3, "1")) == Err(StoredMismatch) and
				PersistenceSnapshot.parse(changed(fields, 2, "00")) == Err(InvalidInteger) and
					PersistenceSnapshot.parse(Json.to_str(fields.append("extra"))) == Err(Malformed) and
						PersistenceSnapshot.parse(Json.to_str(fields.sublist({ start: 0, len: 17 }))) == Err(Malformed)
}
expect {
	PersistenceSnapshot.parse("[[[[") == Err(Malformed) and PersistenceSnapshot.parse("[]") == Err(Malformed) and PersistenceSnapshot.parse("[\"strict-v1\",]") == Err(Malformed) and PersistenceSnapshot.parse("x".repeat(49153)) == Err(TooLarge) and PersistenceSnapshot.parse(Json.to_str(List.repeat("", 2067))) == Err(TooManyTransitions)
}
expect {
	# Escaped metadata is retained exactly; actual outer framing is checked,
	# rather than assuming unescaped string lengths equal encoded lengths.
	control = Str.from_utf8(List.repeat(1.U8, 500))?
	value = fixture("Fixture/Canonical", control, False)?
	text = PersistenceSnapshot.to_text(value)
	envelope = PersistenceEnvelope.new({ format: "roc-time", version: "1", kind: "ixdtf-snapshot", profile: "ixdtf-strict-snapshot-v1", axis: "posix-1970", unit: "microsecond", payload: text })?
	PersistenceEnvelope.to_text(envelope).count_utf8_bytes() <= 65536 and PersistenceSnapshot.parse(text) == Ok(value)
}

fixture = |requested, version, database| {
	validity = PosixSpan.new(
		PosixBoundary.from_microseconds(
			if database {
				-2000000
			} else {
				-10
			},
		),
		PosixBoundary.from_microseconds(
			if database {
				2000000
			} else {
				10
			},
		),
	)?
	rules = ZoneRules.from_definition({
		name: "Fixture/Canonical",
		version,
		validity,
		initial: FixedOffset.from_seconds(0),
		bounds: { minimum: 0, maximum: 3600 },
		provenance: if database {
			DatabaseSource({ requested_name: requested, canonical_name: "Fixture/Canonical", source_digest: "digest\"\\\n😀", profile: "fixture-v1" })
		} else {
			Supplied
		},
		transitions: [
			{
				at: PosixBoundary.from_microseconds(
					if database {
						-1000000
					} else {
						-5
					},
				),
				offset: FixedOffset.from_seconds(0),
			},
			{
				at: PosixBoundary.from_microseconds(
					if database {
						1000000
					} else {
						5
					},
				),
				offset: FixedOffset.from_seconds(3600),
			},
		],
	})?
	source = match Ixdtf.parse("1970-01-01T00:00:00Z[${requested}][u-ca=hebrew]") {
		Ok(value) => value
		Err(error) => return Err(InvalidSource(error))
	}
	bound = match Ixdtf.resolve(source, Some(rules)) {
		Ok(value) => value
		Err(error) => return Err(InvalidSnapshot(error))
	}
	PersistenceSnapshot.from_snapshot(bound)
}

parts : Str -> Try(List(Str), [InvalidJson(Str)])
parts = |text| Json.parse(text)

changed = |fields, index, text| Json.to_str(
	fields.map_with_index(
		|field, i| if i == index {
			text
		} else {
			field
		},
	),
)

expect {
	value = fixture("Fixture/Canonical", "corruption", False)?
	fields = parts(PersistenceSnapshot.to_text(value))?
	PersistenceSnapshot.parse(changed(fields, 2, "9223372036854775808")) == Err(OutOfRange) and
		PersistenceSnapshot.parse(changed(fields, 3, "2147483648")) == Err(OutOfRange) and
			PersistenceSnapshot.parse(changed(fields, 13, "reserved")) == Err(Malformed) and
				PersistenceSnapshot.parse(changed(fields, 17, "1025")) == Err(TooManyTransitions) and
					PersistenceSnapshot.parse("${PersistenceSnapshot.to_text(value)} []") == Err(Malformed)
}
expect {
	value = fixture("Fixture/Alias", "alias", True)?
	fields = parts(PersistenceSnapshot.to_text(value))?
	PersistenceSnapshot.parse(changed(fields, 13, "Fixture/Other")) == Err(InvalidSnapshot(ZoneMismatch)) and
		PersistenceSnapshot.parse(changed(fields, 14, "Fixture/Other")) == Err(InvalidRules(ProvenanceNameMismatch))
}
expect fixture("Fixture/Canonical", "x".repeat(4097), False) == Err(TooLarge)
