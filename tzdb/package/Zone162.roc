import DatabaseRecord
Zone162 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Bangkok", source_version: "2025b", source_digest: "cdc8e2c282d8bc9a5e9c3caf2fc45ff4e9e5cd18f5dec8cb873340ad7c584d64", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 24124.I32, minimum_offset: 24124.I32, maximum_offset: 25200.I32, transitions: [{ second: -2840164924, offset: 24124 }, { second: -1570084924, offset: 25200 }] }
}
