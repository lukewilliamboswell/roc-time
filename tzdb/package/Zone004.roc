import DatabaseRecord
Zone004 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Bissau", source_version: "2025b", source_digest: "c1adeebdad76f5d2474428bbb58b74e2414e9f5fa8b0c4b669f32395e3bd983c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -3740.I32, minimum_offset: -3740.I32, maximum_offset: 0.I32, transitions: [{ second: -1830380400, offset: -3600 }, { second: 157770000, offset: 0 }] }
}
