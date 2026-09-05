import DatabaseRecord
Zone160 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Qatar", source_version: "2025b", source_digest: "6160d6575a371c75b19e6c25cf03160b9dc2f386583e42bf8189fdf8fd17c785", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 12368.I32, minimum_offset: 10800.I32, maximum_offset: 14400.I32, transitions: [{ second: -1577935568, offset: 14400 }, { second: 76190400, offset: 10800 }] }
}
