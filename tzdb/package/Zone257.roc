import DatabaseRecord
Zone257 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+5", source_version: "2025b", source_digest: "4d9e6a6a810b96ccd6fd9e4576a00430a93c63fc6ee5785904d654728e794ab3", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -18000.I32, minimum_offset: -18000.I32, maximum_offset: -18000.I32, transitions: [] }
}
