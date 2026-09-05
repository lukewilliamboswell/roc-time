import DatabaseRecord
Zone270 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-4", source_version: "2025b", source_digest: "73a2b1defe3519192bbe4cbc93bd5d6ff5096e9cb2a763990ac8c34af8e4afab", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 14400.I32, minimum_offset: 14400.I32, maximum_offset: 14400.I32, transitions: [] }
}
