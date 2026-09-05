import DatabaseRecord
Zone321 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Pacific/Fakaofo", source_version: "2025b", source_digest: "51ff3378c2f65fc7683e0f025fea7498c18ff883a3eda1c031eed42c3e648710", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -41096.I32, minimum_offset: -41096.I32, maximum_offset: 46800.I32, transitions: [{ second: -2177411704, offset: -39600 }, { second: 1325242800, offset: 46800 }] }
}
