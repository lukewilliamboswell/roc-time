import DatabaseRecord
Zone144 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Antarctica/Mawson", source_version: "2025b", source_digest: "518ba2052134a99fb69240406ba5eae60f4d5e0f96fd1d0ffab976b653b48c77", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 21600.I32, transitions: [{ second: -501206400, offset: 21600 }, { second: 1255809600, offset: 18000 }] }
}
