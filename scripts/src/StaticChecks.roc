import Text

## Pure repository-layout rules that the check script enforces.
StaticChecks := [].{

	## Problems with compiler pins. The package compiler floats and Blueprint.lock
	## is the only authority for the tooling compiler, so neither a `.roc-version`
	## file nor a `roc` header field may exist.
	pin_problems : Bool, List({ path : Str, source : Str }) -> List(Str)
	pin_problems = |roc_version_exists, sources| {
		version_file = if (roc_version_exists) [".roc-version must not exist: the package compiler is not pinned"] else []
		version_file.concat(
			sources
				.keep_if(|file| Text.pins_compiler(file.source))
				.map(|file| "${file.path}: no header may pin a compiler with a roc field"),
		)
	}

	## Problems with example headers. Repository examples exercise the working
	## tree, so each names the core package, and the zone package when it uses
	## one, by relative path.
	example_problems : List({ path : Str, source : Str }) -> List(Str)
	example_problems = |examples|
		examples
			.keep_if(|file| Text.dependency_values(file.source, "time") != [core_path])
			.map(|file| "${file.path}: the time dependency must be \"${core_path}\"")
			.concat(
				examples
					.keep_if(
						|file| {
							zones = Text.dependency_values(file.source, "zones")
							zones != [] and zones != [zones_path]
						},
					)
					.map(|file| "${file.path}: the zones dependency must be \"${zones_path}\""),
			)

	## Problems with script entry points, which must run on the pinned tooling
	## compiler when executed directly.
	shebang_problems : List({ path : Str, source : Str }) -> List(Str)
	shebang_problems = |scripts|
		scripts
			.keep_if(|file| !file.source.starts_with("${shebang}\n"))
			.map(|file| "${file.path}: scripts must start with ${shebang}")

	## The relative path every repository example uses for the core package.
	core_path : Str
	core_path = "../../package/main.roc"

	## The relative path every repository example uses for the zone package.
	zones_path : Str
	zones_path = "../../tzdb/package/main.roc"
}

shebang = "#!/usr/bin/env roc-stable"

expect StaticChecks.pin_problems(Bool.False, [{ path: "a.roc", source: "app [main!] {\n\tcli: platform \"u\",\n}\n" }]) == []
expect StaticChecks.pin_problems(Bool.True, []) == [".roc-version must not exist: the package compiler is not pinned"]
expect StaticChecks.pin_problems(Bool.False, [{ path: "a.roc", source: "app [main!] {\n\troc: \"nightly-1\",\n}\n" }]) == ["a.roc: no header may pin a compiler with a roc field"]
expect StaticChecks.example_problems([{ path: "e", source: "\ttime: \"../../package/main.roc\",\n" }]) == []
expect StaticChecks.example_problems([{ path: "e", source: "\ttime: \"../../package/main.roc\",\n\tzones: \"../../tzdb/package/main.roc\",\n" }]) == []
expect StaticChecks.example_problems([{ path: "e", source: "\ttime: \"https://example.com/x.tar.zst\",\n" }]) == ["e: the time dependency must be \"../../package/main.roc\""]
expect StaticChecks.example_problems([{ path: "e", source: "app [main!] {}\n" }]) == ["e: the time dependency must be \"../../package/main.roc\""]
expect StaticChecks.example_problems([{ path: "e", source: "\ttime: \"../../package/main.roc\",\n\tzones: \"https://example.com/z.tar.zst\",\n" }]) == ["e: the zones dependency must be \"../../tzdb/package/main.roc\""]
expect StaticChecks.shebang_problems([{ path: "s.roc", source: "#!/usr/bin/env roc-stable\napp [main!] {}\n" }]) == []
expect StaticChecks.shebang_problems([{ path: "s.roc", source: "#!/usr/bin/env roc\napp [main!] {}\n" }]) == ["s.roc: scripts must start with #!/usr/bin/env roc-stable"]
expect StaticChecks.pin_problems(Bool.False, [{ path: "p.roc", source: "package [Database] { roc: \"nightly-1\" }\n" }]) == ["p.roc: no header may pin a compiler with a roc field"]
