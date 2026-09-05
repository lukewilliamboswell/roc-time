import DatabaseRecord
Zone250 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+1", source_version: "2025b", source_digest: "e4bf68f1311482d075d69a086a0f39bd176ad3c2cc0d9999e833e7ed4a8f2ff8", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -3600.I32, minimum_offset: -3600.I32, maximum_offset: -3600.I32, transitions: [] }
}
