import DatabaseRecord
Zone259 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+7", source_version: "2025b", source_digest: "0e2f09e37d161abf7c5b0f79b5d7c8a3c846c645507c9be5c79e5a9ec0eea1e4", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -25200.I32, minimum_offset: -25200.I32, maximum_offset: -25200.I32, transitions: [] }
}
