import DatabaseRecord
Zone036 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Panama", source_version: "2025b", source_digest: "a78d73067ba3cbd94f8a23dfdd6aa8b68cb33b18484bc17b4e20ea1aec2f0a81", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -19088.I32, minimum_offset: -19176.I32, maximum_offset: -18000.I32, transitions: [{ second: -2524502512, offset: -19176 }, { second: -1946918424, offset: -18000 }] }
}
