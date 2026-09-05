import DatabaseRecord
Zone249 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT", source_version: "2025b", source_digest: "dc4a07571b10884e4f4f3450c9d1a1cbf4c03ef53d06ed2e4ea152d9eba5d5d7", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 0.I32, transitions: [] }
}
