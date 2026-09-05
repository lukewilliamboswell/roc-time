import DatabaseRecord
Zone337 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Pitcairn", source_version: "2025b", source_digest: "00987aa252715d0cc231628e139c9ee231df820d5503ef7e80267931bad7ffc1", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -31220.I32, minimum_offset: -31220.I32, maximum_offset: -28800.I32, transitions: [{ second: -2177421580, offset: -30600 }, { second: 893665800, offset: -28800 }] }
}
