import DatabaseRecord
Zone229 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Atlantic/Cape_Verde", source_version: "2025b", source_digest: "139b2ceb1a48a43d20fd5103b053058be96db1e6e9f7c3c14a950ba15c480325", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -5644.I32, minimum_offset: -7200.I32, maximum_offset: -3600.I32, transitions: [{ second: -1830376800, offset: -7200 }, { second: -862610400, offset: -3600 }, { second: -764118000, offset: -7200 }, { second: 186120000, offset: -3600 }] }
}
