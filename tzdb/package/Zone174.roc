import DatabaseRecord
Zone174 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Dili", source_version: "2025b", source_digest: "e5f7021e45486642d5f1372ca8143c1ecb482c4a73ddacb7306194eac80dc4b0", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 30140.I32, minimum_offset: 28800.I32, maximum_offset: 32400.I32, transitions: [{ second: -1830412800, offset: 28800 }, { second: -879152400, offset: 32400 }, { second: 199897200, offset: 28800 }, { second: 969120000, offset: 32400 }] }
}
