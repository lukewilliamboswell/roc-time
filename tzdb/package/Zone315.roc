import DatabaseRecord
Zone315 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Kwajalein", source_version: "2025b", source_digest: "4be6458ba89d2b30da7a52f2ec346318f783d2cee856e777c4b33164a365064f", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 40160.I32, minimum_offset: -43200.I32, maximum_offset: 43200.I32, transitions: [{ second: -2177492960, offset: 39600 }, { second: -1041418800, offset: 36000 }, { second: -907408800, offset: 32400 }, { second: -817462800, offset: 39600 }, { second: -7988400, offset: -43200 }, { second: 745934400, offset: 43200 }] }
}
