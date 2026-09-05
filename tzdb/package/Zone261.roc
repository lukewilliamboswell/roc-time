import DatabaseRecord
Zone261 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT+9", source_version: "2025b", source_digest: "d6fa642283ea062c035b31fe7cb171c0d6e674a458ee6a9d889858408995c5ac", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -32400.I32, minimum_offset: -32400.I32, maximum_offset: -32400.I32, transitions: [] }
}
