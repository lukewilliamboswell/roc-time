import DatabaseRecord
Zone000 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Abidjan", source_version: "2025b", source_digest: "f3e7fcaa0e9840ff4169d3567d8fb5926644848f4963d7acf92320843c5d486e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -968.I32, minimum_offset: -968.I32, maximum_offset: 0.I32, transitions: [{ second: -1830383032, offset: 0 }] }
}
