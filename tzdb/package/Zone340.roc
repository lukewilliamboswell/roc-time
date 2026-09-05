import DatabaseRecord
Zone340 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Tongatapu", source_version: "2025b", source_digest: "9a31a33525004dfc34c8b181d33b0bc73dff2f5b96c4f00d30bf0ae0741020c6", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 44352.I32, minimum_offset: 44352.I32, maximum_offset: 50400.I32, transitions: [{ second: -767189952, offset: 44400 }, { second: -284041200, offset: 46800 }, { second: 939214800, offset: 50400 }, { second: 953384400, offset: 46800 }, { second: 973342800, offset: 50400 }, { second: 980596800, offset: 46800 }, { second: 1004792400, offset: 50400 }, { second: 1012046400, offset: 46800 }, { second: 1478350800, offset: 50400 }, { second: 1484398800, offset: 46800 }] }
}
