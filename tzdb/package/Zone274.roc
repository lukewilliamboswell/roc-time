import DatabaseRecord
Zone274 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-8", source_version: "2025b", source_digest: "92f19053038d0c11bb9e1129ff0112738c65e31357897122bf102fd3d9e4aff8", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 28800.I32, minimum_offset: 28800.I32, maximum_offset: 28800.I32, transitions: [] }
}
