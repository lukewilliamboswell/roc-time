import DatabaseRecord
Zone098 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Martinique", source_version: "2025b", source_digest: "9b7ac2e8ca2073a71cd5af5727c14f21885969214d758931699fa97c7846dd7e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -14660.I32, minimum_offset: -14660.I32, maximum_offset: -10800.I32, transitions: [{ second: -2524506940, offset: -14660 }, { second: -1851537340, offset: -14400 }, { second: 323841600, offset: -10800 }, { second: 338958000, offset: -14400 }] }
}
