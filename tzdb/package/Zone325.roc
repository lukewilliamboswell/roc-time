import DatabaseRecord
Zone325 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Gambier", source_version: "2025b", source_digest: "c8887cea18e90e4d704564d525138e1aa9fdb6473b7bdfceeb3371aacfb00683", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -32388.I32, minimum_offset: -32400.I32, maximum_offset: -32388.I32, transitions: [{ second: -1806678012, offset: -32400 }] }
}
