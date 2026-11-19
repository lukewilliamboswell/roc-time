# Hand-maintained implementation, copied into the generated distributable pack.
# The imported assets are decoded by top-level values at compile time. Runtime
# lookup shares those immutable values; it does not parse text or load files.
import "zones.txt" as zone_text : Str
import "names.txt" as name_text : Str

## Read the immutable IANA time-zone rules distributed with this package.
## Look up a zone by name, then pass its record to the core package's
## ZoneRules.from_database. Rules have an explicit finite validity interval;
## they do not depend on the host's timezone settings or installed database.
Database :: [].{

	## Zone rules and provenance for the core package's ZoneRules.from_database adapter.
	## requested_name preserves the lookup name; canonical_name identifies its target.
	## start_second is inclusive and end_second exclusive, in POSIX seconds since
	## 1970-01-01. Offsets are whole seconds, local minus POSIX. source_version,
	## source_digest and profile describe the supplied rule snapshot.
	Record : { schema : U16, axis : Str, requested_name : Str, canonical_name : Str, source_version : Str, source_digest : Str, profile : Str, future_handling : Str, start_second : I64, end_second : I64, initial_offset : I32, minimum_offset : I32, maximum_offset : I32, transitions : List({ second : I64, offset : I32 }) }

	## Look up an exact, case-sensitive IANA zone name or supported alias, such as
	## Europe/Paris. UnknownZone retains an unrecognized name; no local zone or
	## fallback is selected. The returned immutable record may share rule storage.
	get : Str -> Try(Record, [UnknownZone(Str)])
	get = |name| {
		index = match find_name(name) {
			Found(value) => value
			Missing => return Err(UnknownZone(name))
		}
		zone = match zones.get(index) {
			Ok(value) => value
			Err(_) => crash "Invalid generated zone index"
		}
		Ok({ schema: 1, axis: "posix-seconds-1970", requested_name: name, canonical_name: zone.name, source_version: metadata.version, source_digest: zone.digest, profile: metadata.profile, future_handling: "expanded-through-validity", start_second: metadata.start, end_second: metadata.end, initial_offset: zone.initial, minimum_offset: zone.minimum, maximum_offset: zone.maximum, transitions: zone.transitions })
	}
}

Zone : { name : Str, digest : Str, initial : I32, minimum : I32, maximum : I32, transitions : List({ second : I64, offset : I32 }) }

zone_lines = zone_text.trim().split_on("\n")

metadata = parse_metadata(field(zone_lines, 0))

zones : List(Zone)
zones = zone_lines.drop_first(1).map(parse_zone)

names : List({ key : List(U8), index : U64 })
names = name_text.trim().split_on("\n").map(
	|line| {
		fields = line.split_on("\t")
		{ key: field(fields, 0).to_utf8(), index: zone_index(field(fields, 1)) }
	},
)

# names.txt is generated in ASCII name order; binary search takes O(log n)
# bytewise comparisons over static keys without runtime hashing or byte-list allocation.
find_name = |name| {
	var $low = 0.U64
	var $high = names.len()
	while $low < $high {
		middle = $low + U64.div_trunc_by($high - $low, 2)
		entry = match names.get(middle) {
			Ok(value) => value
			Err(_) => crash "Zone search bounds invariant"
		}
		match compare_name(name, entry.key) {
			EQ => return Found(entry.index)
			LT => {
				$high = middle
			}
			GT => {
				$low = middle + 1
			}
		}
	}
	Missing
}

# The generated ASCII keys are decoded to immutable byte lists at compile time.
# Index them directly while the caller's string uses the compiler's UTF-8 loop;
# retaining and advancing a generic iterator allocates per byte on this nightly.
compare_name : Str, List(U8) -> [LT, EQ, GT]
compare_name = |supplied, key| {
	var $index = 0.U64
	for byte in supplied.iter_utf8() {
		other = match key.get($index) {
			Ok(value) => value
			Err(_) => return GT
		}
		if byte < other {
			return LT
		}
		if byte > other {
			return GT
		}
		$index = $index + 1
	}
	if ($index < key.len()) LT else EQ
}

# R07/R15: a deliberately different recursive pairwise byte model checks empty
# keys, proper prefixes, punctuation, non-ASCII input and long shared prefixes.
# Lookup accepts every Str; unsupported names retain their exact supplied text.
expect {
	values = ["", "A", "A/", "AA", "A_", "B", "é", "Aé", "中", "A中", "A".repeat(64), "${"A".repeat(64)}B"]
	var $valid = True
	for left in values {
		for right in values {
			$valid = $valid and compare_name(left, right.to_utf8()) == test_compare_bytes(left.to_utf8(), right.to_utf8())
		}
	}
	$valid
}

expect {
	["", "Australia/Melbourn", "Australia/Melbourne/", "Australia/Melbourneé", "é", "Asia/東京", "/Etc/UTC"].all(
		|name| match Database.get(name) {
			Err(UnknownZone(actual)) => actual == name
			Ok(_) => False
		},
	)
}

test_compare_bytes : List(U8), List(U8) -> [LT, EQ, GT]
test_compare_bytes = |left, right| match (left, right) {
	([], []) => EQ
	([], _) => LT
	(_, []) => GT
	([a, .. as tail_a], [b, .. as tail_b]) => if (a < b) LT else if (a > b) GT else test_compare_bytes(tail_a, tail_b)
}

# Private text-assets-v1 encoding: tab-separated canonical name, source digest,
# initial/minimum/maximum offsets and semicolon-separated second,offset pairs.
# A dash denotes no transitions. names.txt maps each source name to a row index.
# Assets are generated, hashed and checked through the core adapter before release.
# A malformed asset is a package build defect, never public caller input.
parse_metadata = |line| {
	fields = line.split_on("\t")
	if fields.len() != 5 or field(fields, 0) != "roc-time-tzdb-v1" {
		crash "Unsupported generated zone asset header"
	}
	{ version: field(fields, 1), profile: field(fields, 2), start: second(field(fields, 3)), end: second(field(fields, 4)) }
}

parse_zone : Str -> Zone
parse_zone = |line| {
	fields = line.split_on("\t")
	transition_text = field(fields, 5)
	transitions = if transition_text == "-" {
		[]
	} else {
		transition_text.split_on(";").map(
			|pair| {
				values = pair.split_on(",")
				{ second: second(field(values, 0)), offset: offset(field(values, 1)) }
			},
		)
	}
	{ name: field(fields, 0), digest: field(fields, 1), initial: offset(field(fields, 2)), minimum: offset(field(fields, 3)), maximum: offset(field(fields, 4)), transitions }
}

field = |fields, index| match fields.get(index) {
	Ok(value) => value
	Err(_) => crash "Invalid generated zone fields"
}

zone_index = |text| match U64.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid generated zone index"
}

second = |text| match I64.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid generated transition second"
}

offset = |text| match I32.from_str(text) {
	Ok(value) => value
	Err(_) => crash "Invalid generated offset"
}
