import DatabaseRecord
Zone010 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Johannesburg", source_version: "2025b", source_digest: "d19aebe2435c4e84bf7ae65533d23a9d440f98162e5b4d69c73f783e02299ec8", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 6720.I32, minimum_offset: 5400.I32, maximum_offset: 10800.I32, transitions: [{ second: -2458173120, offset: 5400 }, { second: -2109288600, offset: 7200 }, { second: -860976000, offset: 10800 }, { second: -845254800, offset: 7200 }, { second: -829526400, offset: 10800 }, { second: -813805200, offset: 7200 }] }
}
