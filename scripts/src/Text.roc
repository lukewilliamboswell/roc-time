## Pure source-text helpers shared by the repository scripts.
Text := [].{

	## Replace the one `name: "..."` package dependency line in a Roc app header,
	## keeping its indentation. Everything else in the source is left untouched.
	rewrite_dependency : { source : Str, name : Str, url : Str } -> Try(Str, [ExpectedOneDependency(Str, U64)])
	rewrite_dependency = |{ source, name, url }| {
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
	has_compiler_pin : Str -> Bool
	has_compiler_pin = |source|
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
	is_valid_version : Str -> Bool
	is_valid_version = |value| {
		base = match value.split_on("+") {
			[plain] => plain
			[plain, metadata] if metadata.split_on(".").all(is_version_identifier) => plain
			_ => return Bool.False
		}
		parts = base.split_on("-")
		core = parts.first() ?? ""
		if !(
			match core.split_on(".") {
				[major, minor, patch] => [major, minor, patch].all(is_version_number)
				_ => Bool.False
			}
		) {
			return Bool.False
		}
		if parts.len() == 1 {
			Bool.True
		} else {
			Str.join_with(parts.drop_first(1), "-").split_on(".").all(|identifier| is_version_identifier(identifier) and (!identifier.to_utf8().all(is_version_digit) or is_version_number(identifier)))
		}
	}
}

is_version_digit : U8 -> Bool
is_version_digit = |byte| byte >= '0' and byte <= '9'

is_version_identifier : Str -> Bool
is_version_identifier = |value| !value.is_empty() and value.to_utf8().all(|byte| is_version_digit(byte) or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '-')

is_version_number : Str -> Bool
is_version_number = |value| !value.is_empty() and value.to_utf8().all(is_version_digit) and (value == "0" or !value.starts_with("0"))

is_dependency : Str, Str -> Bool
is_dependency = |line, name| Str.trim_start(line).starts_with("${name}: \"")

indentation : Str -> Str
indentation = |line| {
	trimmed = Str.trim_start(line)
	Str.from_utf8_lossy(Str.to_utf8(line).take_first(Str.to_utf8(line).len() - Str.to_utf8(trimmed).len()))
}

## Rewrite only the requested dependency declaration.
expect Text.rewrite_dependency({
	source: "app [main!] {\n\tpf: platform \"p\",\n\ttime: \"../../package/main.roc\",\n}\n",
	name: "time",
	url: "http://x/y.tar.zst",
}) == Ok("app [main!] {\n\tpf: platform \"p\",\n\ttime: \"http://x/y.tar.zst\",\n}\n")

## Report a missing dependency declaration.
expect Text.rewrite_dependency({
	source: "app [main!] {}\n",
	name: "time",
	url: "u",
}) == Err(ExpectedOneDependency("time", 0))

## Report duplicate dependency declarations.
expect Text.rewrite_dependency({
	source: "\ttime: \"a\",\n\ttime: \"b\",\n",
	name: "time",
	url: "u",
}) == Err(ExpectedOneDependency("time", 2))

## Read matching dependency declarations.
expect Text.dependency_values("\ttime: \"../../package/main.roc\",\n", "time") == ["../../package/main.roc"]

## Ignore a different dependency name.
expect Text.dependency_values("\troc: \"nightly-1\",\n", "time") == []

## Ignore dependency-like text inside source strings.
expect Text.dependency_values("text = \"roc: \\\"x\\\"\"\n", "roc") == []

## Accept an ordinary release version.
expect Text.is_valid_version("0.10.0")

## Accept a release-candidate version.
expect Text.is_valid_version("1.2.3-rc1")

## Reject an empty version.
expect !Text.is_valid_version("")

## Reject a prefixed version.
expect !Text.is_valid_version("v1.0.0")

## Reject traversal in a version.
expect !Text.is_valid_version("1.0.0/../x")

## Reject malformed numeric and prerelease identifiers.
expect !Text.is_valid_version("01.0.0") and !Text.is_valid_version("1.0") and !Text.is_valid_version("1.0.0-") and !Text.is_valid_version("1.0.0-01")

## Validate build metadata separately from prerelease identifiers.
expect Text.is_valid_version("1.0.0-rc.1+build.01") and !Text.is_valid_version("1.0.0+build..1")

## Detect a compiler pin in an app header.
expect Text.has_compiler_pin("app [main!] {\n\troc: \"nightly-1\",\n}\n")

## Detect a compiler pin in a package header.
expect Text.has_compiler_pin("package [Database] { roc: \"nightly-1\" }\n")

## Detect a pin across a multiline header.
expect Text.has_compiler_pin("package\n\t[A]\n\t{ roc: \"nightly-1\" }\n")

## Do not confuse a package dependency with a compiler pin.
expect !Text.has_compiler_pin("app [main!] {\n\ttime: \"../../package/main.roc\",\n}\n")

## Allow an empty package header.
expect !Text.has_compiler_pin("package [Database] {}\n")

## Do not match a dependency whose name merely ends with roc.
expect !Text.has_compiler_pin("\theroc: \"x\",\n")
