import DatabaseRecord
Zone276 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/UTC", source_version: "2025b", source_digest: "fddce1e648a1732ac29afd9a16151b2973cdf082e7ec0c690f7e42be6b598b93", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 0.I32, transitions: [] }
}
