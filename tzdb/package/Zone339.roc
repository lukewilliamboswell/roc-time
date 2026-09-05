import DatabaseRecord
Zone339 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Tahiti", source_version: "2025b", source_digest: "22f72cd3886d8711108f523fe9a00273bd01cb4966c65be180615887ce377b5e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -35896.I32, minimum_offset: -36000.I32, maximum_offset: -35896.I32, transitions: [{ second: -1806674504, offset: -36000 }] }
}
