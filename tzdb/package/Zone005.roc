import DatabaseRecord
Zone005 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Maputo", source_version: "2025b", source_digest: "910c97c091cd34ae7427c83226234ce7b4f2f425c5822d6669c24be62010a792", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 7818.I32, minimum_offset: 7200.I32, maximum_offset: 7818.I32, transitions: [{ second: -1924999818, offset: 7200 }] }
}
