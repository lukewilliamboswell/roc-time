import OffsetTimestamp
import FixedOffset
import PosixBoundary
import LocalDateTime
import ZoneRules
import PosixSpan
import ClockTime

## Internet extended timestamps, rfc9557-microseconds-v1. The base timestamp
## uses OffsetTimestamp's four-digit Gregorian, six-fractional-digit profile.
## RFC 9557 sections 2–5 govern ordered annotations and offset assertions.
## https://www.rfc-editor.org/rfc/rfc9557.html (April 2024).
##
## At most one leading named/numeric zone and 32 ordered key/value annotations.
## Limits: 4096 total UTF-8 bytes, 255 zone-name bytes, 64 key bytes, 256 value
## bytes. Parsing performs no provider lookup. Construction retains O(input)
## storage; bounded duplicate checking is O(tags squared). Serialization uses
## bounded repeated appends, at most O(tags * output) allocation traffic, with
## canonical base text and preserved annotation order/criticality.
## Unknown elective tags and calendar values survive serialization. Experimental
## keys are rejected. Elective duplicate keys select their first value; any
## conflicting duplicate involving a critical tag errors; identical tags are retained.
## Critical tags require understood processing; only u-ca=gregory is supported.
##
## Interpretation uses a strict conflict policy even for elective zone hints.
## Named zones require supplied matching immutable rules; aliases require the
## rules' recorded requested-name provenance. No name guessing or data download.
## Z/-00:00 assert no local offset; numeric +00:00 does. Calendar annotations
## select presentation only, never reinterpret the base Gregorian fields.
## Interpretation uses ZoneRules.offset_at in O(transitions) and retains its
## actual rules. No lazy/budgeted interpretation claim is made. Snapshots expose
## stored results without resolving again. Non-Gregorian presentation errors.
## Numeric zone -00:00 denotes a fixed zero offset, serialized as +00:00.
## No complete ISO, broader-calendar or native persistence claim.
Ixdtf :: { timestamp : OffsetTimestamp, zone : [None, Some(Zone)], tags : List(Tag) }.{
	ZoneId : [Named(Str), Numeric(FixedOffset)]
	Zone : { critical : Bool, identifier : ZoneId }
	Tag : { critical : Bool, key : Str, value : Str }
	Parts : { timestamp : OffsetTimestamp, zone : [None, Some(Zone)], tags : List(Tag) }
	Error : [Base(OffsetTimestamp.Error), Malformed, Incomplete, TooLarge, TooManyAnnotations, InvalidZone, InvalidTag, ExperimentalKey, UnknownCritical, ConflictingCritical, UnsupportedCriticalCalendar]
	ResolveError : [NeedsContext, UnexpectedContext, ZoneMismatch, OffsetConflict, OutsideValidity, OutOfRange]
	profile : Str
	profile = "rfc9557-microseconds-v1"

	new : Parts -> Try(Ixdtf, Error)
	new = |parts| {
		if parts.tags.len() > 32 {
			return Err(TooManyAnnotations)
		}
		var total = OffsetTimestamp.to_text(parts.timestamp).count_utf8_bytes()
		match parts.zone {
			None => {}
			Some(zone) => {
				length = match zone.identifier {
					Named(name) => {
						if name.count_utf8_bytes() > 255 {
							return Err(TooLarge)
						}
						if !valid_zone_name(name) {
							return Err(InvalidZone)
						}
						name.count_utf8_bytes()
					}
					Numeric(offset) => {
						if !valid_offset(offset) {
							return Err(InvalidZone)
						}
						6
					}
				}
				total = total + length + 2 + if zone.critical {
					1
				} else {
					0
				}
			}
		}
		var seen = []
		for tag in parts.tags {
			if tag.key.count_utf8_bytes() > 64 or tag.value.count_utf8_bytes() > 256 {
				return Err(TooLarge)
			}
			if !valid_key(tag.key) or !valid_value(tag.value) {
				return Err(InvalidTag)
			}
			if tag.key.starts_with("_") {
				return Err(ExperimentalKey)
			}
			for previous in seen {
				if previous.key == tag.key and previous.value != tag.value and (previous.critical or tag.critical) {
					return Err(ConflictingCritical)
				}
			}
			seen = seen.append(tag)
			total = total + tag.key.count_utf8_bytes() + tag.value.count_utf8_bytes() + 3 + if tag.critical {
				1
			} else {
				0
			}
		}
		if total > 4096 {
			return Err(TooLarge)
		}
		# Validate conflicts first so critical calendar duplicates are never lost
		# behind first-value processing or unsupported-value processing.
		for tag in parts.tags {
			if tag.critical {
				if tag.key != "u-ca" {
					return Err(UnknownCritical)
				}
				if tag.value != "gregory" {
					return Err(UnsupportedCriticalCalendar)
				}
			}
		}
		Ok({ timestamp: parts.timestamp, zone: parts.zone, tags: parts.tags })
	}
	parts : Ixdtf -> Parts
	parts = |value| { timestamp: value.timestamp, zone: value.zone, tags: value.tags }

	parse : Str -> Try(Ixdtf, Error)
	parse = |text| {
		if text.count_utf8_bytes() > 4096 {
			return Err(TooLarge)
		}
		bytes = text.to_utf8()
		var index = 0.U64
		while index < bytes.len() and at(bytes, index) != 91 {
			index = index + 1
		}
		timestamp = match OffsetTimestamp.parse(piece(bytes, 0, index)) {
			Ok(value) => value
			Err(error) => return Err(Base(error))
		}
		var zone = None
		var tags = []
		while index < bytes.len() {
			if at(bytes, index) != 91 {
				return Err(Malformed)
			}
			index = index + 1
			critical = index < bytes.len() and at(bytes, index) == 33
			if critical {
				index = index + 1
			}
			start = index
			while index < bytes.len() and at(bytes, index) != 93 {
				if at(bytes, index) == 91 {
					return Err(Malformed)
				}
				index = index + 1
			}
			if index == bytes.len() {
				return Err(Incomplete)
			}
			body = piece(bytes, start, index - start)
			index = index + 1
			components = body.split_on("=")
			if components.len() == 1 {
				if zone != None or !tags.is_empty() {
					return Err(Malformed)
				}
				identifier = if body.starts_with("+") or body.starts_with("-") {
					parsed = match OffsetTimestamp.parse("1970-01-01T00:00:00${body}") {
						Ok(value) => value
						Err(_) => return Err(InvalidZone)
					}
					match OffsetTimestamp.parts(parsed).offset {
						Asserted(offset) => Numeric(offset)
						UnassertedUtc => Numeric(FixedOffset.from_seconds(0))
					}
				} else {
					Named(body)
				}
				zone = Some({ critical, identifier })
			} else if components.len() == 2 {
				if tags.len() == 32 {
					return Err(TooManyAnnotations)
				}
				tags = tags.append({ critical, key: item(components, 0), value: item(components, 1) })
			} else {
				return Err(Malformed)
			}
		}
		new({ timestamp, zone, tags })
	}

	preferred_calendar : Ixdtf -> [None, Some(Str)]
	preferred_calendar = |value| {
		for tag in value.tags {
			if tag.key == "u-ca" {
				return Some(tag.value)
			}
		}
		None
	}

	to_text : Ixdtf -> Str
	to_text = |value| {
		var output = OffsetTimestamp.to_text(value.timestamp)
		match value.zone {
			None => {}
			Some(zone) => {
				output = "${output}[${flag(zone.critical)}${zone_text(zone.identifier)}]"
			}
		}
		for tag in value.tags {
			output = "${output}[${flag(tag.critical)}${tag.key}=${tag.value}]"
		}
		output
	}
	is_eq : Ixdtf, Ixdtf -> Bool
	is_eq = |a, b| a.timestamp == b.timestamp and a.zone == b.zone and a.tags == b.tags
	to_hash : Ixdtf, Hasher -> Hasher
	to_hash = |value, hasher| {
		var state = value.timestamp.to_hash(hasher)
		match value.zone {
			None => {
				state = (0.U8).to_hash(state)
			}
			Some(zone) => {
				state = zone.critical.to_hash((1.U8).to_hash(state))
				state = match zone.identifier {
					Named(name) => name.to_hash((0.U8).to_hash(state))
					Numeric(offset) => offset.to_hash((1.U8).to_hash(state))
				}
			}
		}
		for tag in value.tags {
			state = tag.value.to_hash(tag.key.to_hash(tag.critical.to_hash(state)))
		}
		value.tags.len().to_hash(state)
	}
	to_inspect : Ixdtf -> Str
	to_inspect = |value| "Ixdtf(${OffsetTimestamp.to_text(value.timestamp)}, zone=${
		if value.zone == None {
			"absent"
		} else {
			"present"
		}
	}, tags=${value.tags.len().to_str()})"

	## Strict interpretation: supplied context is required exactly for Named.
	## Elective unknown tags are retained without acting on them. Unsupported
	## elective calendars affect presentation, not the already supplied instant.
	resolve : Ixdtf, [None, Some(ZoneRules)] -> Try(Snapshot, ResolveError)
	resolve = |source, context| Snapshot.resolve(source, context)

	Snapshot :: { source : Ixdtf, context : [None, Some(ZoneRules)], boundary : PosixBoundary, offset : FixedOffset, local : LocalDateTime }.{
		resolve : Ixdtf, [None, Some(ZoneRules)] -> Try(Snapshot, ResolveError)
		resolve = |source, context| {
			boundary = match OffsetTimestamp.boundary(source.timestamp) {
				Ok(value) => value
				Err(_) => return Err(OutOfRange)
			}
			offset = match source.zone {
				None => {
					if context != None {
						return Err(UnexpectedContext)
					}
					base_offset(source.timestamp)
				}
				Some(zone) => match zone.identifier {
					Numeric(fixed) => {
						if context != None {
							return Err(UnexpectedContext)
						}
						fixed
					}
					Named(name) => {
						rules = match context {
							None => return Err(NeedsContext)
							Some(value) => value
						}
						matches = name == ZoneRules.name(rules) or match ZoneRules.provenance(rules) {
							Supplied => False
							DatabaseSource(data) => name == data.requested_name
						}
						if !matches {
							return Err(ZoneMismatch)
						}
						match ZoneRules.offset_at(rules, boundary) {
							Ok(value) => value
							Err(_) => return Err(OutsideValidity)
						}
					}
				}
			}
			match OffsetTimestamp.parts(source.timestamp).offset {
				UnassertedUtc => {}
				Asserted(assertion) => if assertion != offset {
					return Err(OffsetConflict)
				}
			}
			local = match FixedOffset.project(offset, boundary, Gregorian) {
				Ok(value) => value
				Err(_) => return Err(OutOfRange)
			}
			Ok({ source, context, boundary, offset, local })
		}
		source : Snapshot -> Ixdtf
		source = |snapshot| snapshot.source
		context : Snapshot -> [None, Some(ZoneRules)]
		context = |snapshot| snapshot.context
		boundary : Snapshot -> PosixBoundary
		boundary = |snapshot| snapshot.boundary
		offset : Snapshot -> FixedOffset
		offset = |snapshot| snapshot.offset

		## Read the stored Gregorian projection only when the requested preferred
		## calendar is supported. An absent preference adds no calendar assertion.
		presentation : Snapshot -> Try(LocalDateTime, [UnsupportedCalendar(Str)])
		presentation = |snapshot| {
			match preferred_calendar(snapshot.source) {
				None => {}
				Some(name) => if name != "gregory" {
					return Err(UnsupportedCalendar(name))
				}
			}
			Ok(snapshot.local)
		}
		reresolve : Snapshot, [None, Some(ZoneRules)] -> Try(Snapshot, ResolveError)
		reresolve = |snapshot, new_context| resolve(snapshot.source, new_context)
		same_position : Snapshot, Snapshot -> Bool
		same_position = |a, b| a.boundary == b.boundary
		to_inspect : Snapshot -> Str
		to_inspect = |snapshot| "Ixdtf.Snapshot(${Str.inspect(snapshot.boundary)}, offset=${Str.inspect(snapshot.offset)})"
	}
}

base_offset = |timestamp| match OffsetTimestamp.parts(timestamp).offset {
	UnassertedUtc => FixedOffset.from_seconds(0)
	Asserted(offset) => offset
}

valid_offset = |offset| {
	seconds = FixedOffset.to_seconds(offset)
	seconds >= -86340 and seconds <= 86340 and I32.rem_by(seconds, 60) == 0
}

flag = |critical| if critical {
	"!"
} else {
	""
}

zone_text = |identifier| match identifier {
	Named(name) => name
	Numeric(offset) => {
		seconds = FixedOffset.to_seconds(offset)
		sign = if seconds < 0 {
			"-"
		} else {
			"+"
		}
		absolute = if seconds < 0 {
			-seconds
		} else {
			seconds
		}
		hours = I32.div_trunc_by(absolute, 3600).to_str()
		minutes = I32.rem_by(I32.div_trunc_by(absolute, 60), 60).to_str()
		"${sign}${"0".repeat(2 - hours.count_utf8_bytes())}${hours}:${"0".repeat(2 - minutes.count_utf8_bytes())}${minutes}"
	}
}

alpha = |byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

lower = |byte| byte >= 97 and byte <= 122

digit = |byte| byte >= 48 and byte <= 57

zone_initial = |byte| alpha(byte) or byte == 46 or byte == 95

valid_zone_name : Str -> Bool
valid_zone_name = |name| {
	if name.is_empty() {
		return False
	}
	for part in name.split_on("/") {
		if part.is_empty() or part == "." or part == ".." {
			return False
		}
		bytes = part.to_utf8()
		if !zone_initial(at(bytes, 0)) {
			return False
		}
		if !bytes.all(|byte| zone_initial(byte) or digit(byte) or byte == 45 or byte == 43) {
			return False
		}
	}
	True
}

valid_key : Str -> Bool
valid_key = |key| {
	bytes = key.to_utf8()
	if bytes.is_empty() {
		return False
	}
	if !(lower(at(bytes, 0)) or at(bytes, 0) == 95) {
		return False
	}
	bytes.all(|byte| lower(byte) or digit(byte) or byte == 95 or byte == 45)
}

valid_value : Str -> Bool
valid_value = |value| {
	if value.is_empty() {
		return False
	}
	value.split_on("-").all(|part| !part.is_empty() and part.to_utf8().all(|byte| alpha(byte) or digit(byte)))
}

at = |bytes, index| match bytes.get(index) {
	Ok(value) => value
	Err(_) => crash "IXDTF byte index bounded by validated input length"
}

item = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "IXDTF split arity checked"
}

piece = |bytes, start, len| match Str.from_utf8(bytes.sublist({ start, len })) {
	Ok(value) => value
	Err(_) => crash "IXDTF substrings end at ASCII brackets in a valid UTF-8 Str"
}

# RFC 9557 §3.3: Paris in July 2022 has +02:00; a Z base does not
# assert +00:00. The fixture covers only the instant needed by this example.
expect {
	source = Ixdtf.parse("2022-07-08T00:14:07Z[Europe/Paris]")?
	point = OffsetTimestamp.boundary(Ixdtf.parts(source).timestamp)?
	rules = test_rules("Europe/Paris", point, 7200)?
	snapshot = Ixdtf.resolve(source, Some(rules))?
	local = Ixdtf.Snapshot.presentation(snapshot)?
	clock = ClockTime.to_fields(LocalDateTime.clock(local))
	asserted = Ixdtf.parse("2022-07-08T00:14:07+00:00[Europe/Paris]")?
	Ixdtf.Snapshot.boundary(snapshot) == point and clock.hour == 2 and clock.minute == 14 and clock.second == 7 and
		resolve_error(Ixdtf.resolve(asserted, Some(rules))) == Some(OffsetConflict) and
			resolve_error(Ixdtf.resolve(source, None)) == Some(NeedsContext) and
				resolve_error(Ixdtf.resolve(source, Some(test_rules("Europe/London", point, 7200)?))) == Some(ZoneMismatch)
}
# RFC9557 §3.3's duplicate elective calendars choose the first, whereas a
# conflicting critical calendar requires error handling. Ordering is retained.
expect {
	value = Ixdtf.parse("2022-07-08T00:14:07Z[u-ca=chinese][u-ca=japanese]")?
	Ixdtf.preferred_calendar(value) == Some("chinese") and
		Ixdtf.to_text(value) == "2022-07-08T00:14:07Z[u-ca=chinese][u-ca=japanese]" and
			Ixdtf.parse("2022-07-08T00:14:07Z[!u-ca=chinese][u-ca=japanese]") == Err(ConflictingCritical) and
				Ixdtf.parse("2022-07-08T00:14:07Z[u-ca=chinese][!u-ca=japanese]") == Err(ConflictingCritical) and
					Ixdtf.parse("2022-07-08T00:14:07Z[!knort=blargel]") == Err(UnknownCritical)
}
expect {
	value = Ixdtf.parse("1996-12-19T16:39:57-08:00[u-ca=hebrew][knort=blargel]")?
	snapshot = Ixdtf.resolve(value, None)?
	Ixdtf.Snapshot.presentation(snapshot) == Err(UnsupportedCalendar("hebrew")) and
		Ixdtf.Snapshot.boundary(snapshot) == OffsetTimestamp.boundary(Ixdtf.parts(value).timestamp)? and
			Ixdtf.parse(Ixdtf.to_text(value)) == Ok(value) and
				Ixdtf.parse("1996-12-19T16:39:57-08:00[!u-ca=hebrew]") == Err(UnsupportedCriticalCalendar)
}
expect {
	value = Ixdtf.parse("1970-01-01t00:00:00z[!-00:00][!u-ca=gregory][u-ca=gregory]")?
	snapshot = Ixdtf.resolve(value, None)?
	Ixdtf.to_text(value) == "1970-01-01T00:00:00Z[!+00:00][!u-ca=gregory][u-ca=gregory]" and
		Ixdtf.Snapshot.boundary(snapshot) == PosixBoundary.from_microseconds(0) and
			Ixdtf.parse(Ixdtf.to_text(value)) == Ok(value) and
				resolve_error(Ixdtf.resolve(value, Some(test_rules("UTC", PosixBoundary.from_microseconds(0), 0)?))) == Some(UnexpectedContext) and
					resolve_error(Ixdtf.resolve(Ixdtf.parse("1970-01-01T00:00:00+01:00[+00:00]")?, None)) == Some(OffsetConflict)
}
expect {
	Ixdtf.parse("1970-01-01T00:00:00Z[_foo=bar]") == Err(ExperimentalKey) and
		Ixdtf.parse("1970-01-01T00:00:00Z[u-ca=gregory][Europe/Paris]") == Err(Malformed) and
			Ixdtf.parse("1970-01-01T00:00:00Z[Europe/Paris][Europe/London]") == Err(Malformed) and
				Ixdtf.parse("1970-01-01T00:00:00Z[Europe/../Paris]") == Err(InvalidZone) and
					Ixdtf.parse("1970-01-01T00:00:00Z[1Europe/Paris]") == Err(InvalidZone) and
						Ixdtf.parse("1970-01-01T00:00:00Z[U-ca=gregory]") == Err(InvalidTag) and
							Ixdtf.parse("1970-01-01T00:00:00Z[knort=a--b]") == Err(InvalidTag) and
								Ixdtf.parse("1970-01-01T00:00:00Z[knort=a=b]") == Err(Malformed) and
									Ixdtf.parse("1970-01-01T00:00:00Z[Europe/Paris") == Err(Incomplete)
}
expect {
	# ASCII bracket slicing never cuts a UTF-8 codepoint; malformed public
	# non-ASCII components return structured errors, not fabricated empty text.
	Ixdtf.parse("1970-01-01T00:00:00Z[Éurope/Paris]") == Err(InvalidZone) and
		Ixdtf.parse("1970-01-01T00:00:00Z[knort=é]") == Err(InvalidTag) and
			Ixdtf.parse("é[Europe/Paris]") == Err(Base(Malformed))
}
expect {
	timestamp = OffsetTimestamp.parse("1970-01-01T00:00:00Z")?
	tag = { key: "knort", value: "a", critical: Bool.False }
	Ixdtf.new({ timestamp, zone: None, tags: List.repeat(tag, 33) }) == Err(TooManyAnnotations) and
		Ixdtf.new({ timestamp, zone: Some({ critical: False, identifier: Named("a".repeat(256)) }), tags: [] }) == Err(TooLarge) and
			Ixdtf.new({ timestamp, zone: Some({ critical: False, identifier: Numeric(FixedOffset.from_seconds(I32.lowest)) }), tags: [] }) == Err(InvalidZone) and
				Ixdtf.new({ timestamp, zone: None, tags: [{ ..tag, key: "a".repeat(65) }] }) == Err(TooLarge) and
					Ixdtf.new({ timestamp, zone: None, tags: [{ ..tag, value: "a".repeat(257) }] }) == Err(TooLarge) and
						Ixdtf.new({ timestamp, zone: None, tags: List.repeat({ ..tag, value: "a".repeat(256) }, 32) }) == Err(TooLarge) and
							Ixdtf.parse("a".repeat(4097)) == Err(TooLarge)
}
expect {
	source = Ixdtf.parse("1970-01-01T00:00:00Z[Synthetic/Rule]")?
	point = PosixBoundary.from_microseconds(0)
	first_rules = test_rules("Synthetic/Rule", point, 0)?
	second_rules = test_rules("Synthetic/Rule", point, 3600)?
	first = Ixdtf.resolve(source, Some(first_rules))?
	second = Ixdtf.Snapshot.reresolve(first, Some(second_rules))?
	Ixdtf.Snapshot.same_position(first, second) and
		Ixdtf.Snapshot.offset(first) == FixedOffset.from_seconds(0) and
			Ixdtf.Snapshot.offset(second) == FixedOffset.from_seconds(3600) and
				Ixdtf.Snapshot.source(first) == source and Ixdtf.Snapshot.source(second) == source
}

test_rules = |name, point, offset| {
	# One microsecond validity: these fixtures assert only the queried instant.
	validity = PosixSpan.microsecond_at(point)?
	ZoneRules.new_bounded(name, "rfc9557-fixture-v1", validity, FixedOffset.from_seconds(offset), [], { minimum: offset, maximum: offset })
}

resolve_error = |result| match result {
	Ok(_) => None
	Err(error) => Some(error)
}

expect {
	# Synthetic provenance fixture: only the declared canonical/requested names
	# match. Similar spelling and an unrecorded alias carry no such evidence.
	rules = ZoneRules.from_database({
		schema: 1,
		axis: "posix-seconds-1970",
		requested_name: "Synthetic/Alias",
		canonical_name: "Synthetic/Canonical",
		source_version: "ixdtf-alias-fixture-v1",
		source_digest: "synthetic-no-upstream-data",
		profile: "synthetic-bounded",
		future_handling: "expanded-through-validity",
		start_second: -1,
		end_second: 1,
		initial_offset: 0,
		minimum_offset: 0,
		maximum_offset: 0,
		transitions: [],
	})?
	alias = Ixdtf.parse("1970-01-01T00:00:00Z[Synthetic/Alias]")?
	canonical = Ixdtf.parse("1970-01-01T00:00:00Z[Synthetic/Canonical]")?
	left = Ixdtf.resolve(alias, Some(rules))?
	right = Ixdtf.resolve(canonical, Some(rules))?
	Ixdtf.Snapshot.same_position(left, right) and Ixdtf.Snapshot.source(left) != Ixdtf.Snapshot.source(right) and
		resolve_error(Ixdtf.resolve(Ixdtf.parse("1970-01-01T00:00:00Z[synthetic/Alias]")?, Some(rules))) == Some(ZoneMismatch) and
			resolve_error(Ixdtf.resolve(Ixdtf.parse("1970-01-01T00:00:00Z[Synthetic/Other]")?, Some(rules))) == Some(ZoneMismatch)
}
