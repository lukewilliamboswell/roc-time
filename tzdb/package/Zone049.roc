import DatabaseRecord
Zone049 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Cayenne", source_version: "2025b", source_digest: "f54454e28d6fe7be7d516ba1f3123dbe768034e71e39e456ebb5e8190bae51af", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -12560.I32, minimum_offset: -14400.I32, maximum_offset: -10800.I32, transitions: [{ second: -1846269040, offset: -14400 }, { second: -71092800, offset: -10800 }] }
}
