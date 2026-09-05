import DatabaseRecord
Zone209 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Yangon", source_version: "2025b", source_digest: "e89d835c811d4da44aa8b386782ce8828df085aa0ee8f25661a9881d2f00e90c", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 23087.I32, minimum_offset: 23087.I32, maximum_offset: 32400.I32, transitions: [{ second: -2840163887, offset: 23087 }, { second: -1577946287, offset: 23400 }, { second: -873268200, offset: 32400 }, { second: -778410000, offset: 23400 }] }
}
