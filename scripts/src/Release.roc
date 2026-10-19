import Text

## Pure release rules: the bundle role manifest, release URLs, the examples
## archive and release notes.
Release := [].{

	## One released archive. `name` is its role: `core` or `zones`.
	Bundle : { name : Str, artifact_file : Str, sha256 : Str }

	## The `roc-time-bundles.json` release asset. Roles are explicit; nothing
	## infers them from archive count or order.
	Manifest : { format : Str, version : U64, bundles : List(Bundle) }

	## Build the manifest for a core and zones archive pair.
	manifest : Bundle, Bundle -> Manifest
	manifest = |core, zones| { format: manifest_format, version: 1, bundles: [core, zones] }

	## Decode and validate a role manifest, returning its core and zones rows.
	parse_manifest : Str -> Try({ core : Bundle, zones : Bundle }, [InvalidManifest(Str)])
	parse_manifest = |json| {
		parsed : Manifest
		parsed = Json.parse(json).map_err(|_| InvalidManifest("not a role manifest"))?
		if parsed.format != manifest_format or parsed.version != 1 {
			return Err(InvalidManifest("unsupported format or version"))
		}
		match (parsed.bundles.keep_if(|row| row.name == "core"), parsed.bundles.keep_if(|row| row.name == "zones")) {
			([core], [zones]) if parsed.bundles.len() == 2 =>
				if !archive_name(core.artifact_file) or !archive_name(zones.artifact_file) {
					Err(InvalidManifest("unsafe archive filename"))
				} else if core.artifact_file == zones.artifact_file {
					Err(InvalidManifest("core and zones must be distinct archives"))
				} else if !digest(core.sha256) or !digest(zones.sha256) {
					Err(InvalidManifest("invalid archive digest"))
				} else {
					Ok({ core, zones })
				}
			_ => Err(InvalidManifest("exactly one core and one zones row are required"))
		}
	}

	## The download URL of a release asset.
	url : Str, Str, Str -> Str
	url = |repository, version, filename| "https://github.com/${repository}/releases/download/${version}/${filename}"

	## The name of the examples archive and of the directory inside it.
	archive_stem : Str -> Str
	archive_stem = |version| "roc-time-examples-${version}"

	## Rewrite an example's `main.roc` for the archive: only the package
	## dependency lines change, to the release's bundle URLs.
	archive_main : Str, Str, Str -> Try(Str, [ExpectedOneDependency(Str, U64)])
	archive_main = |source, core_url, zones_url| {
		with_core = Text.rewrite_dependency(source, "time", core_url)?
		if Text.dependency_values(with_core, "zones").is_empty() {
			Ok(with_core)
		} else {
			Text.rewrite_dependency(with_core, "zones", zones_url)
		}
	}

	## Count the lines on which an archived `main.roc` differs from its
	## repository source, or fail unless every one is a `time` or `zones`
	## dependency line on both sides.
	dependency_only_changes : Str, Str -> Try(U64, [OtherChanges])
	dependency_only_changes = |source, archived| {
		ours = Str.split_on(source, "\n")
		theirs = Str.split_on(archived, "\n")
		if ours.len() != theirs.len() {
			return Err(OtherChanges)
		}
		changed = List.map2(ours, theirs, |left, right| (left, right)).keep_if(|(left, right)| left != right)
		if changed.all(|(left, right)| package_line(left) and package_line(right)) {
			Ok(changed.len())
		} else {
			Err(OtherChanges)
		}
	}

	## The README placed at the root of the examples archive.
	archive_readme : Str, Str, Str, List(Str) -> Str
	archive_readme = |version, core_url, zones_url, names|
		Str.join_with(
			[
				"# roc-time ${version} examples",
				"",
				"Complete applications from the roc-time repository at release ${version}.",
				"Each `examples/<name>/main.roc` depends on this release's packages by URL:",
				"",
				"- `time`: ${core_url}",
				"- `zones`: ${zones_url}",
				"",
				"Install the Roc compiler the release notes name, then run an application:",
				"",
				"```sh",
				"cd examples/booking_exchange",
				"roc main.roc",
				"```",
				"",
				"`expected/<name>.txt` holds the output recorded for this release, where an",
				"application's output is deterministic. `clock_deadline` reads the system",
				"clock and needs network access to fetch its platform.",
				"",
				"Applications: ${Str.join_with(names, ", ")}.",
				"",
			],
			"\n",
		)

	## Release notes text naming both compilers, the packages and their digests.
	notes : { version : Str, repository : Str, roc_version : Str, roc_stable_version : Str, core : Bundle, zones : Bundle } -> Str
	notes = |release| {
		core_url = url(release.repository, release.version, release.core.artifact_file)
		zones_url = url(release.repository, release.version, release.zones.artifact_file)
		examples = "${archive_stem(release.version)}.zip"
		Str.join_with(
			[
				"## Packages",
				"",
				"```roc",
				"app [main!] {",
				"\ttime: \"${core_url}\",",
				"\tzones: \"${zones_url}\",",
				"}",
				"```",
				"",
				"`zones` is optional: it carries the IANA time-zone data and imports no roc-time modules.",
				"",
				"- `time` sha256 `${release.core.sha256}`",
				"- `zones` sha256 `${release.zones.sha256}`",
				"",
				"## Examples",
				"",
				"[${examples}](${url(release.repository, release.version, examples)}) holds the repository's example applications bound to these two URLs.",
				"",
				"## Compilers",
				"",
				"- Built and tested with `roc version`: ${release.roc_version}",
				"- Repository tooling ran on `roc-stable version`: ${release.roc_stable_version}",
				"",
				"The package headers do not pin a compiler. Install the compiler named by `roc version` above, or a later nightly.",
				"",
			],
			"\n",
		)
	}

	## Check the record the real-clock example prints against the wall-clock
	## readings taken just before and after it ran, as second-precision
	## `YYYY-MM-DDTHH:MM:SS` text. This witnesses a current reading, not clock
	## accuracy.
	clock_problem : Str, Str, Str -> Try({}, [InvalidClockRecord(Str)])
	clock_problem = |output, before, after| {
		record : { checked_at : Str, expires_at : Str, expired : Bool }
		record = Json.parse(output).map_err(|_| InvalidClockRecord("not the expected JSON record"))?
		if record.expires_at != "2030-01-01T00:00:00.000000Z" {
			return Err(InvalidClockRecord("expiry changed"))
		}
		if !microsecond_utc(record.checked_at) {
			return Err(InvalidClockRecord("expected exact UTC microsecond text"))
		}
		seconds = Str.from_utf8_lossy(Str.to_utf8(record.checked_at).take_first(19))
		if Text.compare(seconds, before) == Before or Text.compare(seconds, after) == After {
			return Err(InvalidClockRecord("reading is not near the actual host clock"))
		}
		if record.expired != (Text.compare(record.checked_at, record.expires_at) != Before) {
			return Err(InvalidClockRecord("expiry status disagrees with record boundaries"))
		}
		Ok({})
	}
}

manifest_format = "roc-time-release-bundles"

package_line = |line| !Text.dependency_values(line, "time").is_empty() or !Text.dependency_values(line, "zones").is_empty()

archive_name = |filename|
	match Str.split_on(filename, ".tar.zst") {
		[stem, ""] => !stem.is_empty() and Str.to_utf8(stem).all(|byte| ascii_alphanumeric(byte) or byte == '_' or byte == '-')
		_ => Bool.False
	}

digest = |value| Str.to_utf8(value).len() == 64 and Str.to_utf8(value).all(|byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))

ascii_alphanumeric = |byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')

# 2026-10-12T01:02:03.000000Z
microsecond_utc = |text|
	match Str.to_utf8(text) {
		[y1, y2, y3, y4, '-', m1, m2, '-', d1, d2, 'T', h1, h2, ':', n1, n2, ':', s1, s2, '.', f1, f2, f3, f4, f5, f6, 'Z'] =>
			[y1, y2, y3, y4, m1, m2, d1, d2, h1, h2, n1, n2, s1, s2, f1, f2, f3, f4, f5, f6].all(|byte| byte >= '0' and byte <= '9')
		_ => Bool.False
	}

test_sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

test_core = { name: "core", artifact_file: "roc-time-Abc.tar.zst", sha256: test_sha }

test_zones = { name: "zones", artifact_file: "roc-time-tzdb-Xyz.tar.zst", sha256: test_sha }

expect Release.parse_manifest(Json.to_str(Release.manifest(test_core, test_zones))) == Ok({ core: test_core, zones: test_zones })
expect Release.parse_manifest(Json.to_str(Release.manifest(test_zones, test_core))) == Ok({ core: test_core, zones: test_zones })
expect Release.parse_manifest(Json.to_str(Release.manifest(test_core, test_core))) == Err(InvalidManifest("exactly one core and one zones row are required"))
expect Release.parse_manifest(Json.to_str(Release.manifest(test_core, { ..test_zones, artifact_file: "../x.tar.zst" }))) == Err(InvalidManifest("unsafe archive filename"))
expect Release.parse_manifest(Json.to_str(Release.manifest(test_core, { ..test_zones, artifact_file: test_core.artifact_file }))) == Err(InvalidManifest("core and zones must be distinct archives"))
expect Release.parse_manifest(Json.to_str(Release.manifest(test_core, { ..test_zones, sha256: "abc" }))) == Err(InvalidManifest("invalid archive digest"))
expect Release.parse_manifest("[]") == Err(InvalidManifest("not a role manifest"))
expect Release.url("o/r", "0.2.0", "a.tar.zst") == "https://github.com/o/r/releases/download/0.2.0/a.tar.zst"
expect Release.archive_main("app [main!] {\n\ttime: \"../../package/main.roc\",\n}\n", "C", "Z") == Ok("app [main!] {\n\ttime: \"C\",\n}\n")
expect Release.archive_main("app [main!] {\n\ttime: \"../../package/main.roc\",\n\tzones: \"../../tzdb/package/main.roc\",\n}\n", "C", "Z") == Ok("app [main!] {\n\ttime: \"C\",\n\tzones: \"Z\",\n}\n")
expect Release.archive_main("app [main!] {\n\tpf: platform \"P\",\n\ttime: \"../../package/main.roc\",\n}\nimport pf.Utc\n", "C", "Z") == Ok("app [main!] {\n\tpf: platform \"P\",\n\ttime: \"C\",\n}\nimport pf.Utc\n")
expect Release.archive_main("app [main!] {}\n", "C", "Z") == Err(ExpectedOneDependency("time", 0))

test_clock = |checked, expired| "{\"checked_at\":\"${checked}\",\"expired\":${expired},\"expires_at\":\"2030-01-01T00:00:00.000000Z\"}\n"

expect Release.clock_problem(test_clock("2026-10-12T01:02:03.123456Z", "false"), "2026-10-12T01:02:03", "2026-10-12T01:02:04") == Ok({})
expect Release.clock_problem(test_clock("2031-01-01T00:00:00.000000Z", "true"), "2031-01-01T00:00:00", "2031-01-01T00:00:00") == Ok({})
expect Release.clock_problem(test_clock("2026-10-12T01:02:03.123456Z", "true"), "2026-10-12T01:02:03", "2026-10-12T01:02:04") == Err(InvalidClockRecord("expiry status disagrees with record boundaries"))
expect Release.clock_problem(test_clock("2026-10-12T01:02:02.999999Z", "false"), "2026-10-12T01:02:03", "2026-10-12T01:02:04") == Err(InvalidClockRecord("reading is not near the actual host clock"))
expect Release.clock_problem(test_clock("2026-10-12T01:02:03Z", "false"), "2026-10-12T01:02:03", "2026-10-12T01:02:04") == Err(InvalidClockRecord("expected exact UTC microsecond text"))
expect Release.clock_problem("hello\n", "a", "b") == Err(InvalidClockRecord("not the expected JSON record"))

test_main = "app [main!] {\n\ttime: \"../../package/main.roc\",\n\tzones: \"../../tzdb/package/main.roc\",\n}\nimport zones.Database\n"

expect Release.dependency_only_changes(test_main, test_main) == Ok(0)
expect Release.archive_main(test_main, "C", "Z").map_ok(|archived| Release.dependency_only_changes(test_main, archived)) == Ok(Ok(2))
expect Release.dependency_only_changes(test_main, Str.replace_each(test_main, "zones.Database", "zones.Other")) == Err(OtherChanges)
expect Release.dependency_only_changes(test_main, "${test_main}extra = 1\n") == Err(OtherChanges)
