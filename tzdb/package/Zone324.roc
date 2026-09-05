import DatabaseRecord
Zone324 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Galapagos", source_version: "2025b", source_digest: "6752893d94af3bc33f3dacbd58b70d031ce3a3c8a63eb43b1675cd3977d997c7", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -21504.I32, minimum_offset: -21600.I32, maximum_offset: -18000.I32, transitions: [{ second: -1230746496, offset: -18000 }, { second: 504939600, offset: -21600 }, { second: 722930400, offset: -18000 }, { second: 728888400, offset: -21600 }] }
}
