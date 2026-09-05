import DatabaseRecord
Zone332 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Nauru", source_version: "2025b", source_digest: "c1a85938d8eb78d026630850d8259d28c004dd2566e12d9a62f319a9c0254987", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 40060.I32, minimum_offset: 32400.I32, maximum_offset: 43200.I32, transitions: [{ second: -1545131260, offset: 41400 }, { second: -862918200, offset: 32400 }, { second: -767350800, offset: 41400 }, { second: 287418600, offset: 43200 }] }
}
