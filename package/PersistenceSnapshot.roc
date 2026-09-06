import Ixdtf
import ZoneRules
import FixedOffset
import PosixBoundary
import PosixSpan
import PersistenceEnvelope

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
	RulesError : [EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, MissingProvenance, ProvenanceNameMismatch, InvalidDatabaseAlignment]
	Error : [TooLarge, Malformed, TooManyTransitions, UnsupportedPolicy, InvalidInteger, OutOfRange, InvalidSource(Ixdtf.Error), InvalidRules(RulesError), InvalidBounds([EmptySpan, ReversedBounds]), InvalidSnapshot(Ixdtf.ResolveError), StoredMismatch]
	from_snapshot : Ixdtf.Snapshot -> Try(PersistenceSnapshot, [TooLarge, ..])
	from_snapshot = |bound| {
		context = Ixdtf.Snapshot.context(bound)
		match context {
			None => {}
			Some(rules) => {
				definition = ZoneRules.definition(rules)
				if definition.transitions.len() > 1024 or !metadata_fits(definition) {
					return Err(TooLarge)
				}
			}
		}
		var fields = ["strict-v1", Ixdtf.to_text(Ixdtf.Snapshot.source(bound)), PosixBoundary.to_microseconds(Ixdtf.Snapshot.boundary(bound)).to_str(), FixedOffset.to_seconds(Ixdtf.Snapshot.offset(bound)).to_str()]
		match context {
			None => {
				fields = fields.append("none")
			}
			Some(rules) => {
				data = ZoneRules.definition(rules)
				provenance = match data.provenance {
					Supplied => ["supplied", "", "", "", ""]
					DatabaseSource(p) => ["database", p.requested_name, p.canonical_name, p.source_digest, p.profile]
				}
				fields = fields.concat(["rules", data.name, data.version, PosixBoundary.to_microseconds(PosixSpan.start(data.validity)).to_str(), PosixBoundary.to_microseconds(PosixSpan.end(data.validity)).to_str(), FixedOffset.to_seconds(data.initial).to_str(), data.bounds.minimum.to_str(), data.bounds.maximum.to_str()]).concat(provenance).append(data.transitions.len().to_str())
				for transition in data.transitions {
					fields = fields.append(PosixBoundary.to_microseconds(transition.at).to_str()).append(FixedOffset.to_seconds(transition.offset).to_str())
				}
			}
		}
		text = Json.to_str(fields)
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
				if fields.len() < 18 {
					return Err(Malformed)
				}
				count = integer(at(fields, 17))?
				if count < 0 {
					return Err(InvalidInteger)
				}
				if count > 1024 {
					return Err(TooManyTransitions)
				}
				if fields.len() != 18 + count.to_u64_wrap() * 2 {
					return Err(Malformed)
				}
				low = integer(at(fields, 7))?
				high = integer(at(fields, 8))?
				validity = match PosixSpan.new(PosixBoundary.from_microseconds(low), PosixBoundary.from_microseconds(high)) {
					Ok(value) => value
					Err(EmptySpan) => return Err(InvalidBounds(EmptySpan))
					Err(ReversedBounds) => return Err(InvalidBounds(ReversedBounds))
				}
				initial = offset_integer(at(fields, 9))?
				minimum = offset_integer(at(fields, 10))?
				maximum = offset_integer(at(fields, 11))?
				provenance = match at(fields, 12) {
					"supplied" => {
						if at(fields, 13) != "" or at(fields, 14) != "" or at(fields, 15) != "" or at(fields, 16) != "" {
							return Err(Malformed)
						}
						Supplied
					}
					"database" => DatabaseSource({ requested_name: at(fields, 13), canonical_name: at(fields, 14), source_digest: at(fields, 15), profile: at(fields, 16) })
					_ => return Err(Malformed)
				}
				# Validate metadata before allocating the typed transition list.
				base = { name: at(fields, 5), version: at(fields, 6), validity, initial: FixedOffset.from_seconds(initial), bounds: { minimum, maximum }, provenance, transitions: [] }
				if !metadata_fits(base) {
					return Err(TooLarge)
				}
				var transitions = []
				var index = 18.U64
				while index < fields.len() {
					point = integer(at(fields, index))?
					seconds = offset_integer(at(fields, index + 1))?
					transitions = transitions.append({ at: PosixBoundary.from_microseconds(point), offset: FixedOffset.from_seconds(seconds) })
					index = index + 2
				}
				rules = match ZoneRules.from_definition({ ..base, transitions }) {
					Ok(value) => value
					Err(error) => return Err(InvalidRules(error))
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
			Encoding : encoding
			|state| {
				opened = match Encoding.parse_list_start(encoding, state) {
					Ok(v) => v
					Err(e) => return Err(Encoding(e))
				}
				var rest = match opened {
					Uncounted(s) => s
					Counted(_) => return Err(UnsupportedContainer)
				}
				var entries = []
				var done = Bool.False
				while !done {
					next = match Encoding.parse_list_next(encoding, rest) {
						Ok(v) => v
						Err(e) => return Err(Encoding(e))
					}
					match next {
						Done(s) => {
							rest = s
							done = True
						}
						Item(s) => {
							if entries.len() == 2066 {
								return Err(TooManyFields)
							}
							field = match Encoding.parse_str(encoding, s) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							entries = entries.append(field.value)
							after = match Encoding.parse_list_after_item(encoding, field.rest) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							match after {
								Continue(s2) => {
									rest = s2
								}
								Done(s2) => {
									rest = s2
									done = True
								}
							}
						}
					}
				}
				Ok({ value: { values: entries }, rest })
			}
		}
	}
}

metadata_fits : ZoneRules.Definition -> Bool
metadata_fits = |data| {
	name = data.name.count_utf8_bytes()
	version = data.version.count_utf8_bytes()
	if name > 4096 or version > 4096 {
		return False
	}
	total = name + version
	if total > 4096 {
		return False
	}
	match data.provenance {
		Supplied => True
		DatabaseSource(p) => {
			requested = p.requested_name.count_utf8_bytes()
			canonical = p.canonical_name.count_utf8_bytes()
			digest = p.source_digest.count_utf8_bytes()
			profile = p.profile.count_utf8_bytes()
			if requested > 4096 or canonical > 4096 or digest > 4096 or profile > 4096 {
				return False
			}
			total + requested + canonical + digest + profile <= 4096
		}
	}
}

integer : Str -> Try(I64, PersistenceSnapshot.Error)
integer = |text| {
	bytes = text.to_utf8()
	if bytes.is_empty() {
		return Err(InvalidInteger)
	}
	start = if bytes.first() == Ok(45) {
		1.U64
	} else {
		0.U64
	}
	if bytes.len() == start {
		return Err(InvalidInteger)
	}
	digits = bytes.sublist({ start, len: bytes.len() - start })
	if !digits.all(|byte| byte >= 48 and byte <= 57) {
		return Err(InvalidInteger)
	}
	if digits.first() == Ok(48) and (digits.len() > 1 or start == 1) {
		return Err(InvalidInteger)
	}
	match I64.from_str(text) {
		Ok(value) => Ok(value)
		Err(_) => Err(OutOfRange)
	}
}

offset_integer : Str -> Try(I32, PersistenceSnapshot.Error)
offset_integer = |text| {
	value = integer(text)?
	if value < -2147483648 or value > 2147483647 {
		return Err(OutOfRange)
	}
	Ok(value.to_i32_wrap())
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
