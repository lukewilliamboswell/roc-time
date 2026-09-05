import DatabaseRecord
Zone268 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-2", source_version: "2025b", source_digest: "40c4e830b7227f54b848d3ce33132d04ba9cd6c9146272216d40232847407fdc", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 7200.I32, minimum_offset: 7200.I32, maximum_offset: 7200.I32, transitions: [] }
}
