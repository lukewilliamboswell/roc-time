import DatabaseRecord
Zone269 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-3", source_version: "2025b", source_digest: "d7418cbdfba5689c034221e258426253f6144728c37cf725e6e827601ba03771", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 10800.I32, minimum_offset: 10800.I32, maximum_offset: 10800.I32, transitions: [] }
}
