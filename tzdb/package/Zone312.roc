import DatabaseRecord
Zone312 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Indian/Chagos", source_version: "2025b", source_digest: "27f692eebb34646d5d3d319ea245f1349a45e0f76cf2ed5cb78f5c46d5fb8226", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 17380.I32, minimum_offset: 17380.I32, maximum_offset: 21600.I32, transitions: [{ second: -1988167780, offset: 18000 }, { second: 820436400, offset: 21600 }] }
}
