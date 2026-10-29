## The distributed provider's explicit, finite IANA profile. These are
## publication/tooling records; the core adapter remains the interpretation
## boundary. Historical oracle pins are separate (ZoneArchive uses 2025b).
ZoneDistribution := [].{
	version = "2026e"
	revision = "039ef27cc5f062a2055cb67435d6d71adbefd27d"
	profile = "iana-2026e-wheel-2026.5-posix-1800-2200-v1"
	wheel_sha256 = "b683bd1b6659ddcd810ff02ad09ba821d4bf1065072805063eb35c49617905ac"
	wheel_url = "https://files.pythonhosted.org/packages/94/21/1e5995a1c920cce14e4bffae20c665ec10e7ed03ab25e006cd741092b718/tzdata-2026.5-py2.py3-none-any.whl"
	header = "package [Database] {}\n"
	Expectations : Dict(Str, { count : U64, checksum : I64 })
	Metadata : { profile : Str, source_version : Str, source_revision : Str, encoding : Str, wheel_url : Str, wheel_sha256 : Str, zi_sha256 : Str, zone_names : U64, canonical_zones : U64, offset_comparisons : U64, start_second : I64, end_second : I64, transition_expectations : Expectations, names : Dict(Str, Str), limitation : Str }
	source_files = ["scripts/generate_zone_database.roc", "scripts/reference_zone_database.py", "scripts/src/ZoneDistribution.roc", "scripts/src/ZoneVerification.roc", "scripts/templates/zone-verify.roc.txt"]
	Manifest : { profile : Str, source_version : Str, source_revision : Str, encoding : Str, wheel_url : Str, wheel_sha256 : Str, generator_sha256 : Str, generator_adapter_sha256 : Try(Str, [Missing]), reference_adapter_sha256 : Try(Str, [Missing]), generator_source_revision : Try(Str, [Missing]), generator_adapter_sources : Try(Dict(Str, Str), [Missing]), zi_sha256 : Str, zone_names : U64, canonical_zones : U64, offset_comparisons : U64, start_second : I64, end_second : I64, transition_expectations : Expectations, names : Dict(Str, Str), files : Dict(Str, Str), limitation : Str }
	Row : { canonical_name : Str, sha256 : Str, initial : I32, minimum : I32, maximum : I32, transitions : List({ second : I64, offset : I32 }) }
	Reference : { metadata : Metadata, rows : List(Row), identities : List({ name : Str, index : U64 }), licenses : List({ name : Str, bytes : List(U8) }) }

	# Blueprint provisions Unix hosts. Keep native path spelling (including
	# spaces) while removing only trailing separators and the final component.
	parent_path : Str -> Str
	parent_path = |path| {
		stripped = trim_separators(path)
		parent = Str.join_with(stripped.split_on("/").drop_last(1), "/")
		if (parent.is_empty()) "/" else parent
	}
	validate_header : Str -> Try({}, [PackageHeader])
	validate_header = |source| if (source == header) Ok({}) else Err(PackageHeader)
	validate_source : Str, Str -> Try({}, [SourceVersion])
	validate_source = |zi, module_text| if (zi.starts_with("# version ${version}\n") and module_text.contains("IANA_VERSION = \"${version}\"")) Ok({}) else Err(SourceVersion)
	validate_metadata : Manifest -> Try({}, [DistributionMetadata])
	validate_metadata = |manifest| {
		if manifest.source_version != version or manifest.source_revision != revision or manifest.profile != profile or manifest.encoding != "text-assets-v1" or manifest.wheel_url != wheel_url or manifest.wheel_sha256 != wheel_sha256 or manifest.start_second != -5364662400 or manifest.end_second != 7258118400 or manifest.zone_names != manifest.names.len() or manifest.canonical_zones != manifest.transition_expectations.len() or manifest.zone_names == 0 or manifest.zone_names > 1000 or manifest.canonical_zones == 0 or manifest.canonical_zones > manifest.zone_names or manifest.files.contains("main.roc") {
			return Err(DistributionMetadata)
		}
		for (name, canonical) in manifest.names.to_list() {
			if !column(name) or !column(canonical) or !manifest.transition_expectations.contains(canonical) {
				return Err(DistributionMetadata)
			}
		}
		Ok({})
	}
	assets : Reference -> Try({ zones : Str, names : Str }, [ReferenceData])
	assets = |reference| {
		data = reference.metadata
		if data.source_version != version or data.profile != profile or data.source_revision != revision or data.wheel_sha256 != wheel_sha256 or data.wheel_url != wheel_url or data.start_second != -5364662400 or data.end_second != 7258118400 or reference.rows.len() != data.canonical_zones or reference.identities.len() != data.zone_names or data.zone_names > 1000 or data.zone_names == 0 {
			return Err(ReferenceData)
		}
		var $seen = []
		var $lines = []
		for row in reference.rows {
			if !column(row.canonical_name) or $seen.contains(row.canonical_name) or !hash(row.sha256) or row.minimum > row.initial or row.maximum < row.initial or row.minimum > row.maximum or row.transitions.len() > 10000 {
				return Err(ReferenceData)
			}
			$seen = $seen.append(row.canonical_name)
			var $previous = data.start_second
			var $checksum = 0.I128
			var $index = 1.I128
			for transition in row.transitions {
				if transition.second <= $previous or transition.second >= data.end_second or transition.offset < row.minimum or transition.offset > row.maximum {
					return Err(ReferenceData)
				}
				$checksum = $checksum + $index * (transition.second.to_i128() + transition.offset.to_i128())
				$index = $index + 1
				$previous = transition.second
			}
			expected = data.transition_expectations.get(row.canonical_name).map_err(|_| ReferenceData)?
			if row.transitions.len() != expected.count or $checksum != expected.checksum.to_i128() {
				return Err(ReferenceData)
			}
			transitions = if (row.transitions.is_empty()) "-" else Str.join_with(row.transitions.map(|item| "${item.second.to_str()},${item.offset.to_str()}"), ";")
			$lines = $lines.append("${row.canonical_name}\t${row.sha256}\t${row.initial.to_str()}\t${row.minimum.to_str()}\t${row.maximum.to_str()}\t${transitions}")
		}
		var $names = []
		var $seen_names = []
		for identity in reference.identities {
			if !column(identity.name) or $seen_names.contains(identity.name) {
				return Err(ReferenceData)
			}
			canonical = reference.rows.get(identity.index).map_err(|_| ReferenceData)?.canonical_name
			if data.names.get(identity.name) != Ok(canonical) {
				return Err(ReferenceData)
			}
			$seen_names = $seen_names.append(identity.name)
			$names = $names.append("${identity.name}\t${identity.index.to_str()}")
		}
		Ok({ zones: "roc-time-tzdb-v1\t${version}\t${profile}\t${data.start_second.to_str()}\t${data.end_second.to_str()}\n${Str.join_with($lines, "\n")}\n", names: "${Str.join_with($names, "\n")}\n" })
	}
	manifest : Metadata, Str, Str, Dict(Str, Str), Dict(Str, Str) -> Manifest
	manifest = |data, generator_sha256, reference_sha256, files, sources| { profile: data.profile, source_version: data.source_version, source_revision: data.source_revision, encoding: data.encoding, wheel_url: data.wheel_url, wheel_sha256: data.wheel_sha256, generator_sha256, generator_adapter_sha256: Ok(generator_sha256), reference_adapter_sha256: Ok(reference_sha256), generator_source_revision: Err(Missing), generator_adapter_sources: Ok(sources), zi_sha256: data.zi_sha256, zone_names: data.zone_names, canonical_zones: data.canonical_zones, offset_comparisons: data.offset_comparisons, start_second: data.start_second, end_second: data.end_second, transition_expectations: data.transition_expectations, names: data.names, limitation: data.limitation, files }
}

column = |text| !text.is_empty() and text.count_utf8_bytes() <= 256 and !text.to_utf8().any(|byte| byte == '\n' or byte == '\r' or byte == '\t' or byte == 0)

hash = |text| text.count_utf8_bytes() == 64 and text.to_utf8().all(|b| (b >= '0' and b <= '9') or (b >= 'a' and b <= 'f'))
expect ZoneDistribution.validate_header(ZoneDistribution.header) == Ok({})
expect ZoneDistribution.validate_header("package [Database, Extra] {}\n") == Err(PackageHeader)
expect ZoneDistribution.validate_header("package [Database] { other: \"../x/main.roc\" }\n") == Err(PackageHeader)
expect ZoneDistribution.validate_header("${ZoneDistribution.header}extra = 1\n") == Err(PackageHeader)
expect ZoneDistribution.validate_source("# version 2025b\n", "IANA_VERSION = \"2026e\"") == Err(SourceVersion)
expect ZoneDistribution.validate_source("# version 2026e\n", "IANA_VERSION = \"2025b\"") == Err(SourceVersion)
expect ZoneDistribution.validate_source("# version 2026e\n", "IANA_VERSION = \"2026e\"") == Ok({})

trim_separators = |path| if (path.ends_with("/") and path != "/") trim_separators(path.drop_suffix("/")) else path
expect ZoneDistribution.parent_path("/tmp/new") == "/tmp"
expect ZoneDistribution.parent_path("/new/") == "/"
expect ZoneDistribution.parent_path("/tmp/parent /new") == "/tmp/parent "

expect ZoneDistribution.validate_header("package [Database] { roc: \"nightly-invalid\" }\n") == Err(PackageHeader)
