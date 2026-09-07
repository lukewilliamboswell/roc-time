## Strict JSON framing for roc-time persistence. Every field is required and
## string-valued: format, version, kind, profile, axis, unit and payload.
## This module validates framing only; the driver validates metadata values
## (including canonical version "1") and the semantic payload.
##
## Duplicate decoded keys, unknown fields and missing fields fail. Unknown values
## are never skipped or recursively traversed. JSON string/token/container syntax
## comes from the pinned builtin encoding protocol, not a second JSON parser.
## Payload is a string; nested objects/arrays are rejected at that field's start.
##
## parse checks 65536 UTF-8 bytes before decoding. new bounds each source string
## and their combined bytes before checking the encoded size against that limit.
## The seven-field schema bounds traversal and key tracking; serialization may
## allocate escaped output, but never derives fields from opaque native layout.
PersistenceEnvelope :: { data : Fields }.{
	Fields : { format : Str, version : Str, kind : Str, profile : Str, axis : Str, unit : Str, payload : Str }
	Error : [TooLarge, Malformed, UnknownField(Str), DuplicateField(Str), MissingField(Str)]
	new : Fields -> Try(PersistenceEnvelope, Error)
	new = |data| {
		var $total = 0.U64
		for text in [data.format, data.version, data.kind, data.profile, data.axis, data.unit, data.payload] {
			length = text.count_utf8_bytes()
			if length > 65536 {
				return Err(TooLarge)
			}
			$total = $total + length
			if $total > 65536 {
				return Err(TooLarge)
			}
		}
		if Json.to_str(data).count_utf8_bytes() > 65536 {
			return Err(TooLarge)
		}
		Ok({ data: data })
	}
	is_eq : PersistenceEnvelope, PersistenceEnvelope -> Bool
	is_eq = |a, b| a.data == b.data
	fields : PersistenceEnvelope -> Fields
	fields = |value| value.data
	to_text : PersistenceEnvelope -> Str
	to_text = |value| Json.to_str(value.data)
	parse : Str -> Try(PersistenceEnvelope, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 65536 {
			return Err(TooLarge)
		}
		decoded : Try(Raw, [InvalidJson(Str), Encoding([InvalidJson(Str)]), UnknownField(Str), DuplicateField(Str), MissingField(Str), UnsupportedContainer])
		decoded = Json.parse(text)
		raw = match decoded {
			Ok(value) => value
			Err(UnknownField(name)) => return Err(UnknownField(name))
			Err(DuplicateField(name)) => return Err(DuplicateField(name))
			Err(MissingField(name)) => return Err(MissingField(name))
			Err(_) => return Err(Malformed)
		}
		new(Raw.fields(raw))
	}

	Raw :: { format : Str, version : Str, kind : Str, profile : Str, axis : Str, unit : Str, payload : Str }.{
		fields : Raw -> Fields
		fields = |v| { format: v.format, version: v.version, kind: v.kind, profile: v.profile, axis: v.axis, unit: v.unit, payload: v.payload }
		parser_for : encoding -> (state -> Try({ value : Raw, rest : state }, [Encoding(err), UnknownField(Str), DuplicateField(Str), MissingField(Str), UnsupportedContainer, ..]))
			where [
				encoding.parse_dict_start : encoding, state -> Try([Counted({ len : U64, rest : state }), Uncounted(state)], err),
				encoding.parse_dict_next : encoding, state -> Try([Entry(state), Done(state)], err),
				encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
				encoding.parse_dict_after_key : encoding, state -> Try(state, err),
				encoding.parse_dict_after_entry : encoding, state -> Try([Continue(state), Done(state)], err),
			]
		parser_for = |encoding| {
			Encoding : encoding
			|state| {
				opened = match Encoding.parse_dict_start(encoding, state) {
					Ok(v) => v
					Err(e) => return Err(Encoding(e))
				}
				var $rest = match opened {
					Uncounted(s) => s
					Counted(_) => return Err(UnsupportedContainer)
				}
				var $data = { format: "", version: "", kind: "", profile: "", axis: "", unit: "", payload: "" }
				var $seen = []
				var $finished = Bool.False
				while !$finished {
					event = match Encoding.parse_dict_next(encoding, $rest) {
						Ok(v) => v
						Err(e) => return Err(Encoding(e))
					}
					match event {
						Done(s) => {
							$rest = s
							$finished = True
						}
						Entry(s) => {
							key = match Encoding.parse_str(encoding, s) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							if $seen.contains(key.value) {
								return Err(DuplicateField(key.value))
							}
							if !keys.contains(key.value) {
								return Err(UnknownField(key.value))
							}
							$seen = $seen.append(key.value)
							start = match Encoding.parse_dict_after_key(encoding, key.rest) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							field = match Encoding.parse_str(encoding, start) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							# The allowlist is checked before reading values. The default branch
							# returns an error even if this code is later changed inconsistently.
							$data = match key.value {
								"format" => { ..$data, format: field.value }
								"version" => { ..$data, version: field.value }
								"kind" => { ..$data, kind: field.value }
								"profile" => { ..$data, profile: field.value }
								"axis" => { ..$data, axis: field.value }
								"unit" => { ..$data, unit: field.value }
								"payload" => { ..$data, payload: field.value }
								_ => return Err(UnknownField(key.value))
							}
							$rest = field.rest
							after = match Encoding.parse_dict_after_entry(encoding, $rest) {
								Ok(v) => v
								Err(e) => return Err(Encoding(e))
							}
							match after {
								Continue(s2) => {
									$rest = s2
								}
								Done(s2) => {
									$rest = s2
									$finished = True
								}
							}
						}
					}
				}
				for key in keys {
					if !$seen.contains(key) {
						return Err(MissingField(key))
					}
				}
				Ok({ value: { format: $data.format, version: $data.version, kind: $data.kind, profile: $data.profile, axis: $data.axis, unit: $data.unit, payload: $data.payload }, rest: $rest })
			}
		}
	}
}

keys = ["format", "version", "kind", "profile", "axis", "unit", "payload"]

expect {
	value = PersistenceEnvelope.parse("{\"format\":\"roc-time\",\"version\":\"1\",\"kind\":\"test\",\"profile\":\"test-v1\",\"axis\":\"none\",\"unit\":\"none\",\"payload\":\"x\"}")?
	PersistenceEnvelope.fields(value) == { format: "roc-time", version: "1", kind: "test", profile: "test-v1", axis: "none", unit: "none", payload: "x" } and PersistenceEnvelope.parse(PersistenceEnvelope.to_text(value)) == Ok(value)
}
expect {
	PersistenceEnvelope.parse("{\"version\":\"1\",\"version\":\"2\"}") == Err(DuplicateField("version")) and PersistenceEnvelope.parse("{\"vers\\u0069on\":\"1\",\"version\":\"2\"}") == Err(DuplicateField("version")) and PersistenceEnvelope.parse("{}") == Err(MissingField("format")) and PersistenceEnvelope.parse("{\"format\":1}") == Err(Malformed)
}
expect {
	# Unknown values are not skipped: even an unfinished deeply nested value is
	# rejected at its decoded key. This bounds work independently of that nesting.
	PersistenceEnvelope.parse("{\"unknown\":${"[".repeat(10000)}") == Err(UnknownField("unknown")) and PersistenceEnvelope.parse("{\"payload\":${"[".repeat(10000)}") == Err(Malformed)
}
expect {
	data = { format: "roc-time", version: "1", kind: "test", profile: "test-v1", axis: "none", unit: "none", payload: "quoted \" payload \\ with\nnewline" }
	value = PersistenceEnvelope.new(data)?
	PersistenceEnvelope.fields(PersistenceEnvelope.parse(PersistenceEnvelope.to_text(value))?) == data and PersistenceEnvelope.parse("${PersistenceEnvelope.to_text(value)}[]") == Err(Malformed) and PersistenceEnvelope.parse("{\"format\":\"roc-time\",}") == Err(Malformed)
}
expect PersistenceEnvelope.parse(" ".repeat(65537)) == Err(TooLarge)
expect {
	data = { format: "roc-time", version: "1", kind: "test", profile: "test-v1", axis: "none", unit: "none", payload: "\n".repeat(20000) }
	PersistenceEnvelope.new(data) != Err(TooLarge) and PersistenceEnvelope.new({ ..data, payload: "\n".repeat(40000) }) == Err(TooLarge)
}
