import DatabaseRecord
Zone330 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Marquesas", source_version: "2025b", source_digest: "8a5a6b911be7f8dd578e9b5223fd19c148deba890ffb997ae2e2a3441a74931c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -33480.I32, minimum_offset: -34200.I32, maximum_offset: -33480.I32, transitions: [{ second: -1806676920, offset: -34200 }] }
}
