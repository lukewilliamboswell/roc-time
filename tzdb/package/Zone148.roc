import DatabaseRecord
Zone148 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Riyadh", source_version: "2025b", source_digest: "46853e94276af2eea8e86c2f152a871c092df195dc51273b8fc7091faa4b461c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 11212.I32, minimum_offset: 10800.I32, maximum_offset: 11212.I32, transitions: [{ second: -719636812, offset: 10800 }] }
}
