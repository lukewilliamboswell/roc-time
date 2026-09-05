import DatabaseRecord
Zone326 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Guadalcanal", source_version: "2025b", source_digest: "522f0f374b61e2c6f5fa7d19f1c7acccd09e4a213462ee3b42c90d32bf2bf18c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 38388.I32, minimum_offset: 38388.I32, maximum_offset: 39600.I32, transitions: [{ second: -1806748788, offset: 39600 }] }
}
