import DatabaseRecord
Zone262 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-1", source_version: "2025b", source_digest: "4bcd52f59d3e57ed01e54fb44b43e76f1f1fbf6887b701352eb95993e7242eda", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 3600.I32, minimum_offset: 3600.I32, maximum_offset: 3600.I32, transitions: [] }
}
