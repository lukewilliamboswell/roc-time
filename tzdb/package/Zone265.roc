import DatabaseRecord
Zone265 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-12", source_version: "2025b", source_digest: "89f1d5864e5f733646dc60f2fcdbfb62c2cd6b17fcb2d07832bce05940883655", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 43200.I32, minimum_offset: 43200.I32, maximum_offset: 43200.I32, transitions: [] }
}
