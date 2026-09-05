import DatabaseRecord
Zone336 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Palau", source_version: "2025b", source_digest: "5642d1b0a514557a37ceb8405e7f6233ea4ac926c62157f35a8a290e199c78c0", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -54124.I32, minimum_offset: -54124.I32, maximum_offset: 32400.I32, transitions: [{ second: -3944624276, offset: 32276 }, { second: -2177485076, offset: 32400 }] }
}
