import DatabaseRecord
Zone253 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+12", source_version: "2025b", source_digest: "976e97085a7d21b8171af330ecd1e01f32196c7af2d81e6a1987e13031c556bc", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -43200.I32, minimum_offset: -43200.I32, maximum_offset: -43200.I32, transitions: [] }
}
