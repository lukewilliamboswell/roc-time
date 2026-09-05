import DatabaseRecord
Zone266 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-13", source_version: "2025b", source_digest: "08c90e45d5ec692c8bfb83749f7ec2c9cd650abdb666c5b2ba0f7f41955ed04d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 46800.I32, minimum_offset: 46800.I32, maximum_offset: 46800.I32, transitions: [] }
}
