import Text

## Admission of immutable API archive inventories before extraction.
ApiArchive := [].{

	## Only regular files/directories below this release are admitted. Inventories
	## are bounded, unique and must contain a real landing-page file.
	validate : Str, List(Str), Str, Bool -> Try({}, [UnsafeArchive])
	validate = |version, entries, metadata, zip| {
		if !Text.valid_version(version) or entries.is_empty() or entries.len() > 10000 {
			return Err(UnsafeArchive)
		}
		var $seen = []
		for entry in entries {
			name = entry.drop_suffix("/")
			parts = name.split_on("/")
			if parts.first() != Ok(version) or parts.any(|part| part.is_empty() or part == "." or part == "..") or !name.to_utf8().all(safe_byte) or $seen.contains(name) {
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

safe_byte = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '/' or b == '.' or b == '_' or b == '-' or b == '+'

expect ApiArchive.validate("0.1.0", ["0.1.0/", "0.1.0/index.html"], "drwxr-xr-x root 0 root\n-rw-r--r-- root 0 index\n", Bool.False) == Ok({})
expect ApiArchive.validate("0.1.0", ["0.1.0/index.html"], "lrwxrwxrwx index -> elsewhere\n", Bool.False) == Err(UnsafeArchive)
expect ApiArchive.validate("0.1.0", ["0.1.0/index.html", "0.1.0/../escape"], "-file\n-file\n", Bool.False) == Err(UnsafeArchive)
expect ApiArchive.validate("0.1.0", ["0.1.0/index.html", "0.1.0/index.html"], "-file\n-file\n", Bool.False) == Err(UnsafeArchive)
expect ApiArchive.validate("0.1.0", ["0.2.0/index.html"], "-file\n", Bool.False) == Err(UnsafeArchive)
expect ApiArchive.validate("0.1.0", ["0.1.0/other.html"], "-file\n", Bool.False) == Err(UnsafeArchive)
expect ApiArchive.validate("0.1.0", ["0.1.0/index.html", "0.1.0/index.html/child"], "-file\n-file\n", Bool.False) == Err(UnsafeArchive)
