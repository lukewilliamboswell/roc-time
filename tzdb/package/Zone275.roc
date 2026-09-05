import DatabaseRecord
Zone275 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-9", source_version: "2025b", source_digest: "535591146590016f752572bdf606352bd774ac56580d61f30d4477cfbd4b87a6", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 32400.I32, minimum_offset: 32400.I32, maximum_offset: 32400.I32, transitions: [] }
}
