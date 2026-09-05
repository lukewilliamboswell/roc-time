import DatabaseRecord
Zone073 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Guatemala", source_version: "2025b", source_digest: "0463c623897237a20517f4f4931d6ada587753948485bc83a8b16e5bc10509a5", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -21724.I32, minimum_offset: -21724.I32, maximum_offset: -18000.I32, transitions: [{ second: -1617040676, offset: -21600 }, { second: 123055200, offset: -18000 }, { second: 130914000, offset: -21600 }, { second: 422344800, offset: -18000 }, { second: 433054800, offset: -21600 }, { second: 669708000, offset: -18000 }, { second: 684219600, offset: -21600 }, { second: 1146376800, offset: -18000 }, { second: 1159678800, offset: -21600 }] }
}
