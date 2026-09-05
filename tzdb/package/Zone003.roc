import DatabaseRecord
Zone003 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Lagos", source_version: "2025b", source_digest: "e5ef1288571cc56c5276ca966e1c8a675c6747726d758ecafe7effce6eca7be4", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 815.I32, minimum_offset: 0.I32, maximum_offset: 3600.I32, transitions: [{ second: -2035584815, offset: 0 }, { second: -1940889600, offset: 815 }, { second: -1767226415, offset: 1800 }, { second: -1588465800, offset: 3600 }] }
}
