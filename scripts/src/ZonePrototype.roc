## Bounded prototype storage sources and observable checksums. Decoded TZif
## columns come from the pinned CPython reference, never the package under test.
ZonePrototype := [].{
	Payload : { times : List(I64), indices : List(U8), offsets : List(I32), footer : Str, bytes : List(U8) }
	Entry : { name : Str, sha256 : Str, data : Payload }
	Options : { wheel : Str, samples : U64, encoding : Str, smoke : Bool }
	parse : List(Str) -> Try(Options, [Arguments])
	parse = |args| {
		if args.len() > 128 {
			return Err(Arguments)
		}
		found = parse_loop(args, { wheel: "", samples: 3, encoding: "columns", smoke: Bool.False })?
		if found.samples < 1 or found.samples > 10 or (found.wheel.is_empty() and !found.smoke) {
			return Err(Arguments)
		}
		Ok(if (found.smoke) { ..found, samples: 1 } else found)
	}
	export : List(Entry), Str -> Try({ files : List({ name : Str, source : Str }), names : Dict(Str, (Str, Payload)) }, [ReferencePayload])
	export = |entries, encoding| {
		if entries.is_empty() or entries.len() > 1000 or !["columns", "tzif"].contains(encoding) {
			return Err(ReferencePayload)
		}
		var $unique = Dict.empty()
		var $names = Dict.empty()
		var $files = []
		for entry in entries {
			data = entry.data
			if entry.name.is_empty() or entry.name.count_utf8_bytes() > 256 or $names.contains(entry.name) or entry.sha256.count_utf8_bytes() != 64 or data.bytes.len() > 1048576 or data.times.len() > 10000 or data.offsets.len() > 256 or data.indices.len() != data.times.len() or data.indices.any(|index| index.to_u64() >= data.offsets.len()) {
				return Err(ReferencePayload)
			}
			module_name = match $unique.get(entry.sha256) {
				Ok((prior, payload)) if payload == data => prior
				Ok(_) => return Err(ReferencePayload)
				Err(_) => {
					index = $unique.len().to_str()
					name = "Z${"0".repeat(3 - index.count_utf8_bytes())}${index}"
					fields = if (encoding == "tzif") "bytes: ${Json.to_str(data.bytes)}" else "times: ${Json.to_str(data.times)}, indices: ${Json.to_str(data.indices)}, offsets: ${Json.to_str(data.offsets)}, footer: ${Json.to_str(data.footer)}"
					annotation = if (encoding == "tzif") "{ bytes : List(U8) }" else "{ times : List(I64), indices : List(U8), offsets : List(I32), footer : Str }"
					$files = $files.append({ name: "${name}.roc", source: "${name} :: [].{\n data : ${annotation}\n data = { ${fields} }\n}\n" })
					$unique = $unique.insert(entry.sha256, (name, data))
					name
				}
			}
			$names = $names.insert(entry.name, (module_name, data))
		}
		imports_text = Str.join_with($files.map(|file| "import ${file.name.drop_suffix(".roc")}\n"), "")
		names = $names
		matches = Str.join_with(names.to_list().sort_with(|a, b| compare(a.0.to_utf8(), b.0.to_utf8())).map(|(name, (module_name, _))| "  ${Json.to_str(name)} => Ok(${module_name}.data)\n"), "")
		$files = $files.append({ name: "Lookup.roc", source: "${imports_text}Lookup :: [].{\n get = |name| match name {\n${matches}  _ => Err(UnknownZone(name))\n }\n}\n" })
		melbourne = names.get("Australia/Melbourne").map_err(|_| ReferencePayload)?.0
		$files = $files.append({ name: "Melbourne.roc", source: "import ${melbourne}\nMelbourne :: [].{ data = ${melbourne}.data }\n" })
		$files = $files.append({ name: "main.roc", source: "package [Lookup, Melbourne] {}\n" })
		Ok({ files: $files, names })
	}
	expected : Str, Payload, Str -> Try(Str, _)
	expected = |name, data, encoding| {
		var $checksum = I64.from_str(name.count_utf8_bytes().to_str())?
		if encoding == "tzif" {
			for byte in data.bytes {
				$checksum = I64.rem_by($checksum + byte.to_i64(), 1000003)
			}
			Ok("${data.bytes.len().to_str()}|${$checksum.to_str()}\n")
		} else {
			for second in data.times {
				$checksum = I64.rem_by($checksum + I64.rem_by(second, 1000003), 1000003)
			}
			for index in data.indices {
				$checksum = I64.rem_by($checksum + index.to_i64(), 1000003)
			}
			for offset in data.offsets {
				$checksum = I64.rem_by($checksum + offset.to_i64(), 1000003)
			}
			Ok("${data.times.len().to_str()}|${$checksum.to_str()}|${data.footer}\n")
		}
	}
}

parse_loop = |args, found| match args {
	[] => Ok(found)
	["--smoke", .. as rest] => parse_loop(rest, { ..found, smoke: Bool.True })
	["--samples", number, .. as rest] => parse_loop(rest, { ..found, samples: U64.from_str(number).map_err(|_| Arguments)? })
	["--encoding", encoding, .. as rest] if ["columns", "tzif"].contains(encoding) => parse_loop(rest, { ..found, encoding })
	[wheel, .. as rest] if found.wheel.is_empty() and !wheel.starts_with("--") => parse_loop(rest, { ..found, wheel })
	_ => Err(Arguments)
}
expect ZonePrototype.parse([]) == Err(Arguments)
expect ZonePrototype.parse(["--smoke", "--encoding", "invalid"]) == Err(Arguments)
expect ZonePrototype.parse(["fixture.whl", "--samples", "0"]) == Err(Arguments)
expect ZonePrototype.parse(["--smoke", "--encoding", "tzif"]).map_ok(|o| (o.samples, o.encoding)) == Ok((1, "tzif"))

compare = |left, right| match (left, right) {
	([a, .. as aa], [b, .. as bb]) => if (a < b) Before else if (a > b) After else compare(aa, bb)
	([], []) => Same
	([], _) => Before
	(_, []) => After
}

sample = { times: [-1000004.I64], indices: [0.U8], offsets: [0.I32], footer: "fixed", bytes: ['T'.U8, 'Z', 'i', 'f'] }
expect ZonePrototype.expected("x", sample, "columns") == Ok("1|0|fixed\n")
expect ZonePrototype.expected("x", sample, "tzif") == Ok("4|382\n")
expect {
	first = { name: "Australia/Melbourne", sha256: "a".repeat(64), data: sample }
	alias = { ..first, name: "Fixture/MelbourneAlias" }
	ZonePrototype.export([first, alias], "columns").map_ok(|result| (result.files.len(), result.names.get(first.name), result.names.get(alias.name))) == Ok((4, Ok(("Z000", sample)), Ok(("Z000", sample))))
}
expect {
	first = { name: "Australia/Melbourne", sha256: "a".repeat(64), data: sample }
	ZonePrototype.export([first, first], "columns") == Err(ReferencePayload)
}
