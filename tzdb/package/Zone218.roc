import DatabaseRecord
Zone218 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Thimphu", source_version: "2025b", source_digest: "37a77fbdf16f60e45f327af57c7263612b780c139149b2e2ff64feaf67490672", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 21516.I32, minimum_offset: 19800.I32, maximum_offset: 21600.I32, transitions: [{ second: -706341516, offset: 19800 }, { second: 560025000, offset: 21600 }] }
}
