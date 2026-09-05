import DatabaseRecord
Zone328 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Kiritimati", source_version: "2025b", source_digest: "71454698c44182595fb982775f4074ce0d017fe2cfa3d97b2dee63bbcf36771e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -37760.I32, minimum_offset: -38400.I32, maximum_offset: 50400.I32, transitions: [{ second: -2177415040, offset: -38400 }, { second: 307622400, offset: -36000 }, { second: 788868000, offset: 50400 }] }
}
