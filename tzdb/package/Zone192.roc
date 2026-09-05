import DatabaseRecord
Zone192 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Kathmandu", source_version: "2025b", source_digest: "76b8f1bfe072231a1d9e7f8501310e27c0d08048c48f7422860b6477c142c438", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 20476.I32, minimum_offset: 19800.I32, maximum_offset: 20700.I32, transitions: [{ second: -1577943676, offset: 19800 }, { second: 504901800, offset: 20700 }] }
}
