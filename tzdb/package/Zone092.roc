import DatabaseRecord
Zone092 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/La_Paz", source_version: "2025b", source_digest: "da2601c677341c8c00ce5c7e437008f4b6f4188f3b558dbbf6819cae8059495b", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -16356.I32, minimum_offset: -16356.I32, maximum_offset: -12756.I32, transitions: [{ second: -2524505244, offset: -16356 }, { second: -1205954844, offset: -12756 }, { second: -1192307244, offset: -14400 }] }
}
