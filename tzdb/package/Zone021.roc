import DatabaseRecord
Zone021 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Puerto_Rico", source_version: "2025b", source_digest: "abbe8628dd5487c889db816ce3a5077bbb47f6bafafeb9411d92d6ef2f70ce8d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -15865.I32, minimum_offset: -15865.I32, maximum_offset: -10800.I32, transitions: [{ second: -2233035335, offset: -14400 }, { second: -873057600, offset: -10800 }, { second: -769395600, offset: -10800 }, { second: -765399600, offset: -14400 }] }
}
