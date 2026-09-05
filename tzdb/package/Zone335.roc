import DatabaseRecord
Zone335 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Noumea", source_version: "2025b", source_digest: "7b35329fb0185816e5ad96d2b6522d258bbb5c83422e28a1ac205907e065f90c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 39948.I32, minimum_offset: 39600.I32, maximum_offset: 43200.I32, transitions: [{ second: -1829387148, offset: 39600 }, { second: 250002000, offset: 43200 }, { second: 257342400, offset: 39600 }, { second: 281451600, offset: 43200 }, { second: 288878400, offset: 39600 }, { second: 849366000, offset: 43200 }, { second: 857228400, offset: 39600 }] }
}
