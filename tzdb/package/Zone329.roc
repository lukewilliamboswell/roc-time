import DatabaseRecord
Zone329 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Kosrae", source_version: "2025b", source_digest: "a5030b2578a5ca03e19649b48c2a3926e566a6660980b21d89357178fe7d6448", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -47284.I32, minimum_offset: -47284.I32, maximum_offset: 43200.I32, transitions: [{ second: -3944631116, offset: 39116 }, { second: -2177491916, offset: 39600 }, { second: -1743678000, offset: 32400 }, { second: -1606813200, offset: 39600 }, { second: -1041418800, offset: 36000 }, { second: -907408800, offset: 32400 }, { second: -770634000, offset: 39600 }, { second: -7988400, offset: 43200 }, { second: 915105600, offset: 39600 }] }
}
