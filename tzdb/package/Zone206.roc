import DatabaseRecord
Zone206 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Pyongyang", source_version: "2025b", source_digest: "3710b975af284d9e12b621509e5863969f454d1b8c33e5f0b2add8838cb4c640", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 30180.I32, minimum_offset: 30180.I32, maximum_offset: 32400.I32, transitions: [{ second: -1948782180, offset: 30600 }, { second: -1830414600, offset: 32400 }, { second: -768646800, offset: 32400 }, { second: 1439564400, offset: 30600 }, { second: 1525446000, offset: 32400 }] }
}
