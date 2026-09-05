import DatabaseRecord
Zone147 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Antarctica/Rothera", source_version: "2025b", source_digest: "5de75d44bd984c37c45b3408ee70ea7d6f937e0fb911e6f1b07b0c1f2cc6b9d2", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: -10800.I32, maximum_offset: 0.I32, transitions: [{ second: 218246400, offset: -10800 }] }
}
