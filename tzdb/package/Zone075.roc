import DatabaseRecord
Zone075 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Guyana", source_version: "2025b", source_digest: "3e69c4b56b4e4da9ac3c95c4a3b3dc3500b2d91a7e7af1b2261e1c7f4a63011e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -13959.I32, minimum_offset: -14400.I32, maximum_offset: -10800.I32, transitions: [{ second: -1843589241, offset: -14400 }, { second: -1730577600, offset: -13500 }, { second: 176096700, offset: -10800 }, { second: 701841600, offset: -14400 }] }
}
