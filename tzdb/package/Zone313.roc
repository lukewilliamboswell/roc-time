import DatabaseRecord
Zone313 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Indian/Maldives", source_version: "2025b", source_digest: "94485f0f58f842767ec2db93539d5fc3afb2bdce16673d9e63c0988cccd6438e", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 17640.I32, minimum_offset: 17640.I32, maximum_offset: 18000.I32, transitions: [{ second: -2840158440, offset: 17640 }, { second: -315636840, offset: 18000 }] }
}
