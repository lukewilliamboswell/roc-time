import DatabaseRecord
Zone048 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Caracas", source_version: "2025b", source_digest: "507994c1cd2614fa22751e140c259be13e30fe6a4206c49be01916dd238a2156", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -16064.I32, minimum_offset: -16200.I32, maximum_offset: -14400.I32, transitions: [{ second: -2524505536, offset: -16060 }, { second: -1826739140, offset: -16200 }, { second: -157750200, offset: -14400 }, { second: 1197183600, offset: -16200 }, { second: 1462086000, offset: -14400 }] }
}
