import DatabaseRecord
Zone318 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Bougainville", source_version: "2025b", source_digest: "aea767d58e0749aaf1faf8cf934d25b0735f863dc842028256202cba6b8dfc86", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 37336.I32, minimum_offset: 32400.I32, maximum_offset: 39600.I32, transitions: [{ second: -2840178136, offset: 35312 }, { second: -2366790512, offset: 36000 }, { second: -868010400, offset: 32400 }, { second: -768906000, offset: 36000 }, { second: 1419696000, offset: 39600 }] }
}
