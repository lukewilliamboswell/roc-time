app [main!] {}

main! = |args| {
	count = U64.from_str(args.get(0) ?? "2") ?? 2
	var $entries = []
	var $index = 0.U64
	while $index < count {
		ending = if args.get(1) == Ok("boundary") {
			AtBoundary(2.I64)
		} else if args.get(1) == Ok("local") {
			AtLocal("local-end")
		} else {
			After(2.I64)
		}
		$entries = $entries.append({ source: "source-${$index.to_str()}", ending })
		$index = $index + 1
	}
	fields = convert(1.I64, $entries)
	echo!("${Str.inspect(fields)}\n")
	echo!("${Json.to_str(fields)}\n")
	Ok({})
}

duration_fields = |duration| ["coordinate", duration.to_str()]

convert = |duration, overrides| {
	var $fields = duration_fields(duration).append(overrides.len().to_str())
	for entry in overrides {
		ending_fields = match entry.ending {
			After(value) => ["after"].concat(duration_fields(value))
			AtBoundary(value) => ["boundary", value.to_str()]
			AtLocal(value) => ["local", value].concat(["unique", "", "reject"])
		}
		$fields = $fields.concat([entry.source].concat(ending_fields))
	}
	$fields
}
