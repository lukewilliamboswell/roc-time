import DatabaseRecord
Zone191 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Urumqi", source_version: "2025b", source_digest: "849cafd377611cc2fc2b41891ab63c6fb3343949045db961fd16267593315ad4", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 21020.I32, minimum_offset: 21020.I32, maximum_offset: 21600.I32, transitions: [{ second: -1325483420, offset: 21600 }] }
}
