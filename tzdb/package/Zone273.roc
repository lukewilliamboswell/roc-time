import DatabaseRecord
Zone273 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Etc/GMT-7", source_version: "2025b", source_digest: "0e7b1327735461818b53015bfcbd7953f19b68c17e69c2d5b0fc933724b21fe3", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 25200.I32, minimum_offset: 25200.I32, maximum_offset: 25200.I32, transitions: [] }
}
