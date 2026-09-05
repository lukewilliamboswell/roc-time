import DatabaseRecord
Zone323 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Tarawa", source_version: "2025b", source_digest: "09035620bd831697a3e9072f82de34cfca5e912d50c8da547739aa2f28fb6d8e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 41524.I32, minimum_offset: 41524.I32, maximum_offset: 43200.I32, transitions: [{ second: -2177494324, offset: 43200 }] }
}
