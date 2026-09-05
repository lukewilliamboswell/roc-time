import DatabaseRecord
Zone188 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Kabul", source_version: "2025b", source_digest: "a4d2304df8921bbd4118abeb84aaa8d71771724031f6f7dcc799c96a7acbf354", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 16608.I32, minimum_offset: 14400.I32, maximum_offset: 16608.I32, transitions: [{ second: -2524538208, offset: 14400 }, { second: -788932800, offset: 16200 }] }
}
