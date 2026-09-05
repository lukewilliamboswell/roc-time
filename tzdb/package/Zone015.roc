import DatabaseRecord
Zone015 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Sao_Tome", source_version: "2025b", source_digest: "3df8aeb5a930e41e71af5392835b85bd3d06c02ea354eaaac67c7af46109bb9d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 1616.I32, minimum_offset: -2205.I32, maximum_offset: 3600.I32, transitions: [{ second: -2713912016, offset: -2205 }, { second: -1830384000, offset: 0 }, { second: 1514768400, offset: 3600 }, { second: 1546304400, offset: 0 }] }
}
