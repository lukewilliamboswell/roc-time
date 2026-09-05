import DatabaseRecord
Zone255 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+3", source_version: "2025b", source_digest: "ab70fd0cb7e64c1500a3860c9cd50d5142ab024292c0ce50faf7ac77d03a4994", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -10800.I32, minimum_offset: -10800.I32, maximum_offset: -10800.I32, transitions: [] }
}
