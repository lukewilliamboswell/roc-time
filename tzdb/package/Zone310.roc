import DatabaseRecord
Zone310 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Factory", source_version: "2025b", source_digest: "d32b579ed0a7427316bea260b9ee2675451046bd58c57c679c24f2671860af76", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 0.I32, transitions: [] }
}
