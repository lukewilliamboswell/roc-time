import DatabaseRecord
Zone267 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-14", source_version: "2025b", source_digest: "34ad3b125c2e794d0e3fc80e46d717514ba0ff7bf8774e2ec5f5473149cb33d5", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 50400.I32, minimum_offset: 50400.I32, maximum_offset: 50400.I32, transitions: [] }
}
