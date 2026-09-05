import DatabaseRecord
Zone117 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Paramaribo", source_version: "2025b", source_digest: "0b6bfdb51ea7a39e024440960c5840353978d14b00e00847b1d9c6a0d09be3f4", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -13240.I32, minimum_offset: -13252.I32, maximum_offset: -10800.I32, transitions: [{ second: -1861906760, offset: -13252 }, { second: -1104524348, offset: -13236 }, { second: -765317964, offset: -12600 }, { second: 465449400, offset: -10800 }] }
}
