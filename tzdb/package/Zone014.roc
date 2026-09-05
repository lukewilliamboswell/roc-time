import DatabaseRecord
Zone014 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Africa/Ndjamena", source_version: "2025b", source_digest: "4e58f865450d271121bc0a28ed324aa96bf527bb4461a7f514431ecfe2bdc448", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 3612.I32, minimum_offset: 3600.I32, maximum_offset: 7200.I32, transitions: [{ second: -1830387612, offset: 3600 }, { second: 308703600, offset: 7200 }, { second: 321314400, offset: 3600 }] }
}
