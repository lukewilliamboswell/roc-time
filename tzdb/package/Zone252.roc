import DatabaseRecord
Zone252 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+11", source_version: "2025b", source_digest: "f4c7c5a45a7faedf4f92c323436dd53a58abde1cd39672f3ff9576b5fa2785b5", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -39600.I32, minimum_offset: -39600.I32, maximum_offset: -39600.I32, transitions: [] }
}
