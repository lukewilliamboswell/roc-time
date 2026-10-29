## Admission of this repository's authored single-line TOML metadata profile.
## Values remain JSON-compatible scalars/arrays; this is not a TOML parser.
OracleManifest := [].{
	Manifest : {
		profile : Str,
		corpus_sha256 : Str,
		smoke_sha256 : Str,
		generator_sha256 : Str,
		generator_adapter_sha256 : Str,
		case_count : U64,
		smoke_case_count : U64,
		gap_sha256 : Str,
		gap_count : U64,
	}
	parse : Str, Str -> Try(Manifest, [OracleMetadata])
	parse = |source, name| {
		if source.count_utf8_bytes() > 131072 {
			return Err(OracleMetadata)
		}
		var $fields = Dict.empty()
		for raw in source.split_on("\n") {
			line = raw.trim()
			if !line.is_empty() and !line.starts_with("#") {
				(key, value) = match line.split_on(" = ") {
					[field, .. as values] if !values.is_empty() => (field, Str.join_with(values, " = "))
					_ => return Err(OracleMetadata)
				}
				if key.is_empty() or $fields.contains(key) or !key.to_utf8().all(|b| (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '_') {
					return Err(OracleMetadata)
				}
				$fields = $fields.insert(key, value)
			}
		}
		fields = $fields
		text = |key| Json.parse(fields.get(key).map_err(|_| OracleMetadata)?).map_err(|_| OracleMetadata)
		number = |key| U64.from_str(fields.get(key).map_err(|_| OracleMetadata)?).map_err(|_| OracleMetadata)
		profile : Str
		profile = text("profile")?
		wanted = match name {
			"gregorian" => "gregorian-i32-years-civil-day-1970-v1"
			"julian" => "julian-i32-years-civil-day-1970-v1"
			"zones" => "zones-tzdata-2025b-v2"
			"calendar_pattern" => "gregorian-calendar-patterns-v1"
			"rfc_date" => "rfc5545-date-values-v1"
			"rfc_timed" => "rfc5545-timed-values-v1"
			_ => return Err(OracleMetadata)
		}
		if profile != wanted or number("version")? != 2 or text("corpus_format")? != "jsonl-v1" {
			return Err(OracleMetadata)
		}
		case_count = number("case_count")?
		smoke_case_count = number("smoke_case_count")?
		if case_count == 0 or case_count > 4096 or smoke_case_count == 0 or smoke_case_count > case_count {
			return Err(OracleMetadata)
		}
		corpus_sha256 = text("corpus_sha256")?
		smoke_sha256 = text("smoke_sha256")?
		generator_sha256 = text("generator_sha256")?
		generator_adapter_sha256 = if (fields.contains("generator_adapter_sha256")) text("generator_adapter_sha256")? else generator_sha256
		gap_sha256 = if (name == "calendar_pattern") text("reference_gap_sha256")? else ""
		gap_count = if (name == "calendar_pattern") number("reference_gap_count")? else 0
		if ![corpus_sha256, smoke_sha256, generator_sha256, generator_adapter_sha256].all(is_sha256) or (name == "calendar_pattern" and !is_sha256(gap_sha256)) {
			return Err(OracleMetadata)
		}
		Ok({
			profile,
			corpus_sha256,
			smoke_sha256,
			generator_sha256,
			generator_adapter_sha256,
			case_count,
			smoke_case_count,
			gap_sha256,
			gap_count,
		})
	}
}

is_sha256 : Str -> Bool
is_sha256 = |text| text.count_utf8_bytes() == 64 and text.to_utf8().all(|b| (b >= '0' and b <= '9') or (b >= 'a' and b <= 'f'))

## Reject duplicate metadata keys.
expect OracleManifest.parse("version = 2\nversion = 2", "gregorian") == Err(OracleMetadata)

## Reject unsupported metadata tables.
expect OracleManifest.parse("[unsupported]\n", "gregorian") == Err(OracleMetadata)

## Require a complete lowercase SHA-256 digest.
expect !is_sha256("a".repeat(63)) and !is_sha256("z".repeat(64)) and is_sha256("a".repeat(64))
