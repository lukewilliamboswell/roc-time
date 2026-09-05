import DatabaseRecord
Zone074 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Guayaquil", source_version: "2025b", source_digest: "f0e21a0b2f928ab28acf823bee5e8c4050e048b1ed8cdd13be494b54467fd34f", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -19160.I32, minimum_offset: -19160.I32, maximum_offset: -14400.I32, transitions: [{ second: -2524502440, offset: -18840 }, { second: -1230749160, offset: -18000 }, { second: 722926800, offset: -14400 }, { second: 728884800, offset: -18000 }] }
}
