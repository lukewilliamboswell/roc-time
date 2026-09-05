import DatabaseRecord
Zone142 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Port_Moresby", source_version: "2025b", source_digest: "683001055b6ef9dc9d88734e0eddd1782f1c3643b7c13a75e9cf8e9052006e19", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 35320.I32, minimum_offset: 35312.I32, maximum_offset: 36000.I32, transitions: [{ second: -2840176120, offset: 35312 }, { second: -2366790512, offset: 36000 }] }
}
