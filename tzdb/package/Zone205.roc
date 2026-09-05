import DatabaseRecord
Zone205 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Pontianak", source_version: "2025b", source_digest: "a34c748cd4e5c23894a80cc65ff1e5cef08caeedb3514460438c73a52f79c5db", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 26240.I32, minimum_offset: 25200.I32, maximum_offset: 32400.I32, transitions: [{ second: -1946186240, offset: 26240 }, { second: -1172906240, offset: 27000 }, { second: -881220600, offset: 32400 }, { second: -766054800, offset: 27000 }, { second: -683883000, offset: 28800 }, { second: -620812800, offset: 27000 }, { second: -189415800, offset: 28800 }, { second: 567964800, offset: 25200 }] }
}
