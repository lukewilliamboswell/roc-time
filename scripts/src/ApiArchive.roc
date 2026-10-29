import Text

## Admission of immutable API archive inventories before extraction.
ApiArchive := [].{

	## Only regular files/directories below this release are admitted. Inventories
	## are bounded, unique and must contain a real landing-page file.
	validate : { version : Str, entries : List(Str), metadata : Str, zip : Bool } -> Try({}, [UnsafeArchive])
	validate = |{ version, entries, metadata, zip }| {
		if !Text.is_valid_version(version) or entries.is_empty() or entries.len() > 10000 {
			return Err(UnsafeArchive)
		}
		var $seen = []
		for entry in entries {
			name = entry.drop_suffix("/")
			parts = name.split_on("/")
			if parts.first() != Ok(version) or parts.any(|part| part.is_empty() or part == "." or part == "..") or !name.to_utf8().all(is_safe_byte) or $seen.contains(name) {
				return Err(UnsafeArchive)
			}
			$seen = $seen.append(name)
			for other in entries {
				if !entry.ends_with("/") and other.starts_with("${entry}/") {
					return Err(UnsafeArchive)
				}
			}
		}
		# zipinfo and GNU tar expose Unix entry types as the first byte. Count
		# every admitted row, so links/special files cannot hide among headers.
		rows = metadata.split_on("\n").keep_if(|line| line.starts_with("-") or line.starts_with("d"))
		var $bytes = 0.U64
		for row in rows {
			fields = row.split_on(" ").keep_if(|field| !field.is_empty())
			size = match fields.get(if (zip) 3 else 2) {
				Ok(value) => U64.from_str(value).map_err(|_| UnsafeArchive)?
				Err(_) => return Err(UnsafeArchive)
			}
			if size > 100000000 or $bytes > 100000000 - size {
				return Err(UnsafeArchive)
			}
			$bytes = $bytes + size
		}
		if rows.len() != entries.len() or !entries.contains("${version}/index.html") {
			Err(UnsafeArchive)
		} else {
			Ok({})
		}
	}
}

is_safe_byte : U8 -> Bool
is_safe_byte = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '/' or b == '.' or b == '_' or b == '-' or b == '+'

## Admit a regular archive rooted at its release version.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/", "0.1.0/index.html"],
	metadata: "drwxr-xr-x root 0 root\n-rw-r--r-- root 0 index\n",
	zip: Bool.False,
}) == Ok({})

## Reject symbolic links in API archives.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/index.html"],
	metadata: "lrwxrwxrwx index -> elsewhere\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)

## Reject traversal outside the version directory.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/index.html", "0.1.0/../escape"],
	metadata: "-file\n-file\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)

## Reject duplicate archive members.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/index.html", "0.1.0/index.html"],
	metadata: "-file\n-file\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)

## Reject an archive for a different release.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.2.0/index.html"],
	metadata: "-file\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)

## Require the version landing page.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/other.html"],
	metadata: "-file\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)

## Reject a file that is also an ancestor directory.
expect ApiArchive.validate({
	version: "0.1.0",
	entries: ["0.1.0/index.html", "0.1.0/index.html/child"],
	metadata: "-file\n-file\n",
	zip: Bool.False,
}) == Err(UnsafeArchive)
