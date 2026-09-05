import DatabaseRecord
Zone263 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-10", source_version: "2025b", source_digest: "56f746e48a5707fc495f8a26cdfaeb1db964454ce46c26573e14eb2e781ceef9", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 36000.I32, minimum_offset: 36000.I32, maximum_offset: 36000.I32, transitions: [] }
}
