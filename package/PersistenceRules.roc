import ZoneRules
import FixedOffset
import PosixBoundary
import PosixSpan

## Shared native rule fields for bound-result persistence. Header order is name,
## version, validity start/end (I64 POSIX microseconds), initial/minimum/maximum
## offsets (I32 seconds), provenance marker, requested/canonical names, digest,
## provenance profile, transition count, then boundary/offset pairs. Supplied
## provenance has four empty reserved strings. This preserves microsecond rules;
## native from_definition validates database provenance and seconds alignment.
## Maximum 1024 transitions and 4096 combined metadata UTF-8 bytes. fits is an
## allocation-free preflight; internal callers must check it before to_fields.
PersistenceRules := [].{
	RulesError : [EmptyName, EmptyVersion, TransitionOutsideValidity, UnorderedTransitions, InvalidOffsetBounds, OffsetOutsideBounds, MissingProvenance, ProvenanceNameMismatch, InvalidDatabaseAlignment]
	Error : [TooLarge, Malformed, TooManyTransitions, InvalidInteger, OutOfRange, InvalidRules(RulesError), InvalidBounds([EmptySpan, ReversedBounds])]
	fits : ZoneRules -> Bool
	fits = |rules| {
		data = ZoneRules.definition(rules)
		data.transitions.len() <= 1024 and metadata_fits(data)
	}
	to_fields : ZoneRules -> List(Str)
	to_fields = |rules| {
		data = ZoneRules.definition(rules)
		provenance = match data.provenance {
			Supplied => ["supplied", "", "", "", ""]
			DatabaseSource(p) => ["database", p.requested_name, p.canonical_name, p.source_digest, p.profile]
		}
		var $fields = [data.name, data.version, PosixBoundary.to_microseconds(PosixSpan.start(data.validity)).to_str(), PosixBoundary.to_microseconds(PosixSpan.end(data.validity)).to_str(), FixedOffset.to_seconds(data.initial).to_str(), data.bounds.minimum.to_str(), data.bounds.maximum.to_str()].concat(provenance).append(data.transitions.len().to_str())
		for transition in data.transitions {
			$fields = $fields.append(PosixBoundary.to_microseconds(transition.at).to_str()).append(FixedOffset.to_seconds(transition.offset).to_str())
		}
		$fields
	}
	from_fields : List(Str) -> Try(ZoneRules, Error)
	from_fields = |fields| {
		if fields.len() < 13 {
			return Err(Malformed)
		}
		count = PersistenceRules.integer(at(fields, 12))?
		if count < 0 {
			return Err(InvalidInteger)
		}
		if count > 1024 {
			return Err(TooManyTransitions)
		}
		if fields.len() != 13 + count.to_u64_wrap() * 2 {
			return Err(Malformed)
		}
		low = PersistenceRules.integer(at(fields, 2))?
		high = PersistenceRules.integer(at(fields, 3))?
		validity = match PosixSpan.new(PosixBoundary.from_microseconds(low), PosixBoundary.from_microseconds(high)) {
			Ok(value) => value
			Err(EmptySpan) => return Err(InvalidBounds(EmptySpan))
			Err(ReversedBounds) => return Err(InvalidBounds(ReversedBounds))
		}
		initial = PersistenceRules.offset_integer(at(fields, 4))?
		minimum = PersistenceRules.offset_integer(at(fields, 5))?
		maximum = PersistenceRules.offset_integer(at(fields, 6))?
		provenance = match at(fields, 7) {
			"supplied" => {
				if at(fields, 8) != "" or at(fields, 9) != "" or at(fields, 10) != "" or at(fields, 11) != "" {
					return Err(Malformed)
				}
				Supplied
			}
			"database" => DatabaseSource({ requested_name: at(fields, 8), canonical_name: at(fields, 9), source_digest: at(fields, 10), profile: at(fields, 11) })
			_ => return Err(Malformed)
		}
		# Validate metadata before allocating the typed transition list.
		base = { name: at(fields, 0), version: at(fields, 1), validity, initial: FixedOffset.from_seconds(initial), bounds: { minimum, maximum }, provenance, transitions: [] }
		if !metadata_fits(base) {
			return Err(TooLarge)
		}
		var $transitions = []
		var $index = 13.U64
		while $index < fields.len() {
			point = PersistenceRules.integer(at(fields, $index))?
			seconds = PersistenceRules.offset_integer(at(fields, $index + 1))?
			$transitions = $transitions.append({ at: PosixBoundary.from_microseconds(point), offset: FixedOffset.from_seconds(seconds) })
			$index = $index + 2
		}
		rules = match ZoneRules.from_definition({ ..base, transitions: $transitions }) {
			Ok(value) => value
			Err(error) => return Err(InvalidRules(error))
		}
		Ok(rules)
	}
	integer : Str -> Try(I64, Error)
	integer = |text| parse_integer(text)
	offset_integer : Str -> Try(I32, Error)
	offset_integer = |text| parse_offset_integer(text)
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

parse_integer : Str -> Try(I64, PersistenceRules.Error)
parse_integer = |text| {
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

parse_offset_integer : Str -> Try(I32, PersistenceRules.Error)
parse_offset_integer = |text| {
	value = parse_integer(text)?
	if value < -2147483648 or value > 2147483647 {
		return Err(OutOfRange)
	}
	Ok(value.to_i32_wrap())
}

at = |values, index| match values.get(index) {
	Ok(value) => value
	Err(_) => crash "Rule header length and transition pair arity validated"
}
