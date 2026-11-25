import time.Interchange.Ixdtf as Ixdtf

IxdtfPrefixes := {}

# RFC 9557 §4.1 permits extending a suffix key until `=` commits it.
# §3.3 requires an error when disagreeing duplicates include a critical tag.
# roc-time's profile recognizes only gregory as a critical calendar and caps
# raw text at 4096 bytes. In each case the independent oracle names a shortest
# accepted completion. An elective key needs `=x]`; a key already used by a
# critical tag either grows by one letter or keeps its exact prior value.
# Compare an unrelated critical zone too: its flag cannot constrain a tag.
expect {
	cases = [
		{ before: "", open: "[u-ca", finish: "=x]" },
		{ before: "[!Etc/UTC]", open: "[u-ca", finish: "=x]" },
		{ before: "[u-ca=hebrew]", open: "[u-ca", finish: "=x]" },
		{ before: "[!u-ca=gregory]", open: "[u-c", finish: "=x]" },
		{ before: "[!u-ca=gregory]", open: "[u-caa", finish: "=x]" },
		{ before: "[!u-ca=gregory]", open: "[u-ca", finish: "a=x]" },
		{ before: "[!u-ca=gregory]", open: "[u-ca=", finish: "gregory]" },
		{ before: "[!u-ca=gregory]", open: "[u-ca=g", finish: "regory]" },
		{ before: "[!u-ca=gregory]", open: "[u-ca=gregory", finish: "]" },
		{ before: "[!u-ca=gregory]", open: "[!u-ca", finish: "=gregory]" },
	]
	for case in cases {
		minimum = case.finish.count_utf8_bytes()
		for spare in [minimum - 1, minimum] {
			prefix = padded_prefix(case.before, case.open, spare)
			closed = "${prefix}${case.finish}"
			if spare >= minimum {
				if Ixdtf.parse(prefix) != Err(Incomplete) or Ixdtf.parse(closed).is_err() {
					crash "IXDTF missed a completion with ${spare.to_str()} available bytes: ${case.before}${case.open} + ${case.finish}"
				}
			} else if Ixdtf.parse(prefix) != Err(TooLarge) or Ixdtf.parse(closed) != Err(TooLarge) {
				crash "IXDTF admitted an impossible prefix with ${spare.to_str()} available bytes: ${case.before}${case.open}"
			}
		}
	}
	True
}

expect {
	# With exactly three bytes left an elective duplicate can close only
	# with a one-byte value. A different key needs one more byte. With nine
	# remaining the exact critical value can be repeated without conflict.
	blocked = padded_prefix("[!u-ca=gregory]", "[u-ca", 3)
	fresh_key = padded_prefix("[!u-ca=gregory]", "[u-ca", 4)
	same_value = padded_prefix("[!u-ca=gregory]", "[u-ca", 9)
	committed_conflict = padded_prefix("[!u-ca=gregory]", "[u-ca=h", 0)
	Ixdtf.parse("${blocked}=g]") == Err(ConflictingCritical) and
		Ixdtf.parse("${blocked}a=x]") == Err(TooLarge) and
			Ixdtf.parse("${fresh_key}a=x]").is_ok() and
				Ixdtf.parse("${same_value}=gregory]").is_ok() and
					Ixdtf.parse("${same_value}=hebrew]") == Err(ConflictingCritical) and
						Ixdtf.parse(committed_conflict) == Err(ConflictingCritical) and
							Ixdtf.parse("${committed_conflict}e") == Err(TooLarge)
}

padded_prefix : Str, Str, U64 -> Str
padded_prefix = |before, open, spare| {
	# Fifteen individually valid elective tags leave room for exactly one
	# adjustable padding tag. Repeated elective keys retain their values.
	padding = "[pad=${"a".repeat(256)}]".repeat(15)
	base = "1970-01-01T00:00:00Z${before}${padding}"
	width = 4096 - spare - base.count_utf8_bytes() - open.count_utf8_bytes() - 6
	"${base}[pad=${"b".repeat(width)}]${open}"
}
