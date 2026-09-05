import DatabaseRecord
Zone320 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Kanton", source_version: "2025b", source_digest: "a23386fa8aa2db91ce9d8e811616afff76e65a0d4b0c82d3e2ffa4c4e155baa2", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: -43200.I32, maximum_offset: 46800.I32, transitions: [{ second: -1020470400, offset: -43200 }, { second: 307627200, offset: -39600 }, { second: 788871600, offset: 46800 }] }
}
