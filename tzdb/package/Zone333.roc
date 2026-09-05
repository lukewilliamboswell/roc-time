import DatabaseRecord
Zone333 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Niue", source_version: "2025b", source_digest: "f1659e6ed8029eb3012a3b8b3446045a592d348da8a769242a093455ccfc19a3", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -40780.I32, minimum_offset: -40800.I32, maximum_offset: -39600.I32, transitions: [{ second: -543069620, offset: -40800 }, { second: -173623200, offset: -39600 }] }
}
