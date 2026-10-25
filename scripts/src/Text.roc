## Pure source-text helpers shared by the repository scripts.
Text := [].{

	## Replace the one `name: "..."` package dependency line in a Roc app header,
	## keeping its indentation. Everything else in the source is left untouched.
	rewrite_dependency : Str, Str, Str -> Try(Str, [ExpectedOneDependency(Str, U64)])
	rewrite_dependency = |source, name, url| {
		lines = Str.split_on(source, "\n")
		count = lines.count_if(|line| is_dependency(line, name))
		if count == 1 {
			Ok(
				Str.join_with(
					lines.map(
						|line|
							if is_dependency(line, name) {
								"${indentation(line)}${name}: \"${url}\","
							} else {
								line
							},
					),
					"\n",
				),
			)
		} else {
			Err(ExpectedOneDependency(name, count))
		}
	}

	## The quoted value of each `name: "..."` dependency line in a Roc source file.
	dependency_values : Str, Str -> List(Str)
	dependency_values = |source, name|
		Str.split_on(source, "\n")
			.keep_if(|line| is_dependency(line, name))
			.map(
				|line|
					match Str.split_on(line, "\"") {
						[_, value, ..] => value
						_ => ""
					},
			)

	## Whether a Roc source file's header pins a compiler with a `roc` field,
	## on a line of its own or inside a one-line header.
	pins_compiler : Str -> Bool
	pins_compiler = |source|
		Str.split_on(source, "\n").any(
			|line|
				match Str.split_on(line, "roc: \"") {
					[_] | [] => Bool.False
					[before, ..] =>
						match Str.to_utf8(before).last() {
							Ok(byte) => byte == ' ' or byte == '\t' or byte == '{' or byte == ','
							Err(_) => Bool.True
						}
				},
		)

	## Whether `value` is a release version such as `0.10.0` or `1.2.3-rc1`:
	## it starts with a digit and holds only ASCII letters, digits, `.` and `-`.
	valid_version : Str -> Bool
	valid_version = |value|
		match Str.to_utf8(value) {
			[first, .. as rest] => (first >= '0' and first <= '9') and rest.all(version_byte)
			[] => Bool.False
		}
}

version_byte = |byte|
	(byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '.' or byte == '-'

is_dependency = |line, name| Str.trim_start(line).starts_with("${name}: \"")

indentation = |line| {
	trimmed = Str.trim_start(line)
	Str.from_utf8_lossy(Str.to_utf8(line).take_first(Str.to_utf8(line).len() - Str.to_utf8(trimmed).len()))
}

expect Text.rewrite_dependency("app [main!] {\n\tpf: platform \"p\",\n\ttime: \"../../package/main.roc\",\n}\n", "time", "http://x/y.tar.zst") == Ok("app [main!] {\n\tpf: platform \"p\",\n\ttime: \"http://x/y.tar.zst\",\n}\n")
expect Text.rewrite_dependency("app [main!] {}\n", "time", "u") == Err(ExpectedOneDependency("time", 0))
expect Text.rewrite_dependency("\ttime: \"a\",\n\ttime: \"b\",\n", "time", "u") == Err(ExpectedOneDependency("time", 2))
expect Text.dependency_values("\ttime: \"../../package/main.roc\",\n", "time") == ["../../package/main.roc"]
expect Text.dependency_values("\troc: \"nightly-1\",\n", "time") == []
expect Text.dependency_values("text = \"roc: \\\"x\\\"\"\n", "roc") == []
expect Text.valid_version("0.10.0")
expect Text.valid_version("1.2.3-rc1")
expect !Text.valid_version("")
expect !Text.valid_version("v1.0.0")
expect !Text.valid_version("1.0.0/../x")
expect Text.pins_compiler("app [main!] {\n\troc: \"nightly-1\",\n}\n")
expect Text.pins_compiler("package [Database] { roc: \"nightly-1\" }\n")
expect Text.pins_compiler("package\n\t[A]\n\t{ roc: \"nightly-1\" }\n")
expect !Text.pins_compiler("app [main!] {\n\ttime: \"../../package/main.roc\",\n}\n")
expect !Text.pins_compiler("package [Database] {}\n")
expect !Text.pins_compiler("\theroc: \"x\",\n")
