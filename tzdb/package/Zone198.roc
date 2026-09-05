import DatabaseRecord
Zone198 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Makassar", source_version: "2025b", source_digest: "355f63fd14ee894e3b9af26f7ca13c75a5c7e4015827c2a2e20bc70494b1c8b7", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 28656.I32, minimum_offset: 28656.I32, maximum_offset: 32400.I32, transitions: [{ second: -1577951856, offset: 28656 }, { second: -1172908656, offset: 28800 }, { second: -880272000, offset: 32400 }, { second: -766054800, offset: 28800 }] }
}
