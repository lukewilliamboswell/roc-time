## Hand-maintained implementation, copied into the generated distributable pack.
## The imported assets are decoded by top-level values at compile time. Runtime
## lookup shares those immutable values; it does not parse text or load files.
import "zones.txt" as zone_text : Str
import "names.txt" as name_text : Str

Database :: [].{
	Record : { schema : U16, axis : Str, requested_name : Str, canonical_name : Str, source_version : Str, source_digest : Str, profile : Str, future_handling : Str, start_second : I64, end_second : I64, initial_offset : I32, minimum_offset : I32, maximum_offset : I32, transitions : List({ second : I64, offset : I32 }) }
	get : Str -> Try(Record, [UnknownZone(Str), ..])
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

names : List({ name : Str, index : U64 })
names = name_text.trim().split_on("\n").map(
	|line| {
		fields = line.split_on("\t")
		{ name: field(fields, 0), index: zone_index(field(fields, 1)) }
	},
)

# names.txt is generated in ASCII name order; binary search takes O(log n)
# bytewise comparisons without hashing or allocating temporary byte lists.
find_name = |name| {
	var low = 0.U64
	var high = names.len()
	while low < high {
		middle = low + U64.div_trunc_by(high - low, 2)
		entry = match names.get(middle) {
			Ok(value) => value
			Err(_) => crash "Zone search bounds invariant"
		}
		match compare_name(name, entry.name) {
			EQ => return Found(entry.index)
			LT => {
				high = middle
			}
			GT => {
				low = middle + 1
			}
		}
	}
	Missing
}

compare_name = |a, b| {
	var right = b.iter_utf8()
	for left in a.iter_utf8() {
		match right.next() {
			One({ item, rest }) => {
				if left < item {
					return LT
				}
				if left > item {
					return GT
				}
				right = rest
			}
			Done => return GT
			# Str.iter_utf8 yields every byte and never emits Skip.
			Skip(_) => crash "UTF-8 iterator invariant"
		}
	}
	if a.count_utf8_bytes() < b.count_utf8_bytes() {
		LT
	} else {
		EQ
	}
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
