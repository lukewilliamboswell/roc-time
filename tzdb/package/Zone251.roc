import DatabaseRecord
Zone251 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+10", source_version: "2025b", source_digest: "22f0718aa414efaab335bbb1468f0087dacf4124464062a9fd246ce6ed4f3e43", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -36000.I32, minimum_offset: -36000.I32, maximum_offset: -36000.I32, transitions: [] }
}
