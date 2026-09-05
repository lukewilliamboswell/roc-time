import DatabaseRecord
Zone190 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Karachi", source_version: "2025b", source_digest: "ba3a38c2ffb7a1af6d7eb153e63b0b70461c8de19e051806d90c1d5e0fe28d4e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 16092.I32, minimum_offset: 16092.I32, maximum_offset: 23400.I32, transitions: [{ second: -1988166492, offset: 19800 }, { second: -862637400, offset: 23400 }, { second: -764145000, offset: 19800 }, { second: -576135000, offset: 18000 }, { second: 38775600, offset: 18000 }, { second: 1018119600, offset: 21600 }, { second: 1033840800, offset: 18000 }, { second: 1212260400, offset: 21600 }, { second: 1225476000, offset: 18000 }, { second: 1239735600, offset: 21600 }, { second: 1257012000, offset: 18000 }] }
}
