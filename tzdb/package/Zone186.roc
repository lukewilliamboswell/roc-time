import DatabaseRecord
Zone186 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Jayapura", source_version: "2025b", source_digest: "0546b4917d6239d7f413ebfbe35e61ee5d2542fe03042617ff77406d8990d315", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 33768.I32, minimum_offset: 32400.I32, maximum_offset: 34200.I32, transitions: [{ second: -1172913768, offset: 32400 }, { second: -799491600, offset: 34200 }, { second: -189423000, offset: 32400 }] }
}
