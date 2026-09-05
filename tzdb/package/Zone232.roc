import DatabaseRecord
Zone232 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Atlantic/South_Georgia", source_version: "2025b", source_digest: "90f19f08b403d82ebf5dce53c809aa9973fe19874b2cfb9ca419f74bbc9b5aef", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -8768.I32, minimum_offset: -8768.I32, maximum_offset: -7200.I32, transitions: [{ second: -2524512832, offset: -7200 }] }
}
