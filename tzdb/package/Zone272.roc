import DatabaseRecord
Zone272 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-6", source_version: "2025b", source_digest: "ddf1fc797fbed220e28e66004074342145e179ecda8faf9a69d66c40d001e1f1", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 21600.I32, minimum_offset: 21600.I32, maximum_offset: 21600.I32, transitions: [] }
}
