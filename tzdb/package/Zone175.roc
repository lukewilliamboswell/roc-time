import DatabaseRecord
Zone175 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Dubai", source_version: "2025b", source_digest: "0d9ea5053e83188032a6fb4d301d5db688f43011e5b6b1f917a11b71a0da7b16", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 13272.I32, minimum_offset: 13272.I32, maximum_offset: 14400.I32, transitions: [{ second: -1577936472, offset: 14400 }] }
}
