import DatabaseRecord
Zone311 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Honolulu", source_version: "2025b", source_digest: "1daa5729aa1e0f32cd44be112d01ad4cc567a9fe76d87dcbb9182be8d2c88ff0", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -37886.I32, minimum_offset: -37886.I32, maximum_offset: -34200.I32, transitions: [{ second: -2334101314, offset: -37800 }, { second: -1157283000, offset: -34200 }, { second: -1155436200, offset: -37800 }, { second: -880198200, offset: -34200 }, { second: -769395600, offset: -34200 }, { second: -765376200, offset: -37800 }, { second: -712150200, offset: -36000 }] }
}
