## Integrity-pinned tzdata payload accounting. Sizes describe ZIP entry
## payloads, not compiler output, runtime allocation or retained memory.
ZoneArchive := [].{
	sha256 = "1a403fada01ff9221ca8044d701868fa132215d84beb92242d9acd2147f667a8"
	url = "https://files.pythonhosted.org/packages/5c/23/c7abc0ca0a1526a0774eca151daeb8de62ec457e77262b66b359c3c7679e/tzdata-2025.2-py2.py3-none-any.whl"
	Entry : { name : Str, expanded : U64, compressed : U64 }
	# Parse only zoneinfo file rows from unzip's fixed -lv columns. The caller
	# verifies the wheel hash before invoking unzip or admitting any row.
	entries : Str -> Try(List(Entry), [ArchiveInventory])
	entries = |listing| {
		var $entries = []
		for line in listing.split_on("\n") {
			fields = line.split_on(" ").keep_if(|field| !field.is_empty())
			if line.contains("tzdata/zoneinfo/") {
				if fields.len() != 8 {
					return Err(ArchiveInventory)
				}
				name = fields.get(7).map_err(|_| ArchiveInventory)?
				if !name.starts_with("tzdata/zoneinfo/") or name.ends_with("/") or $entries.any(|entry| entry.name == name) {
					return Err(ArchiveInventory)
				}
				expanded = U64.from_str(fields.get(0).map_err(|_| ArchiveInventory)?).map_err(|_| ArchiveInventory)?
				compressed = U64.from_str(fields.get(2).map_err(|_| ArchiveInventory)?).map_err(|_| ArchiveInventory)?
				if expanded > 1048576 or compressed > 1048576 {
					return Err(ArchiveInventory)
				}
				$entries = $entries.append({ name, expanded, compressed })
			}
		}
		if $entries.is_empty() or $entries.len() > 10000 {
			return Err(ArchiveInventory)
		}
		Ok($entries)
	}
}

## Read a bounded zone member from the archive inventory.
expect ZoneArchive.entries("1103 Defl:N 586 47% 2025-03-23 13:54 3183bc6f tzdata/zoneinfo/CET\n") == Ok([{ name: "tzdata/zoneinfo/CET", expanded: 1103, compressed: 586 }])

## Reject extra inventory columns.
expect ZoneArchive.entries("1103 Defl:N 586 47% 2025-03-23 13:54 CRC tzdata/zoneinfo/CET extra\n") == Err(ArchiveInventory)

## Reject negative archive member sizes.
expect ZoneArchive.entries("-1 Defl:N 586 47% date time CRC tzdata/zoneinfo/CET\n") == Err(ArchiveInventory)

## Reject oversized expanded archive members.
expect ZoneArchive.entries("1048577 Defl:N 586 47% date time CRC tzdata/zoneinfo/CET\n") == Err(ArchiveInventory)

## Require at least one inventory entry.
expect ZoneArchive.entries("") == Err(ArchiveInventory)
