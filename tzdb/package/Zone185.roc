import DatabaseRecord
Zone185 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Jakarta", source_version: "2025b", source_digest: "e2a099ea48b1f7166b88d219b326f7c44373d08909cd9723b44346946fd6a384", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 25632.I32, minimum_offset: 25200.I32, maximum_offset: 32400.I32, transitions: [{ second: -3231299232, offset: 25632 }, { second: -1451719200, offset: 26400 }, { second: -1172906400, offset: 27000 }, { second: -876641400, offset: 32400 }, { second: -766054800, offset: 27000 }, { second: -683883000, offset: 28800 }, { second: -620812800, offset: 27000 }, { second: -189415800, offset: 25200 }] }
}
