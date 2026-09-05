import DatabaseRecord
Zone314 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Indian/Mauritius", source_version: "2025b", source_digest: "47aa5d25a96b1d52b92e518e984b320faebff9ce5af69b4933ec44ef5168f214", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 13800.I32, minimum_offset: 13800.I32, maximum_offset: 18000.I32, transitions: [{ second: -1988164200, offset: 14400 }, { second: 403041600, offset: 18000 }, { second: 417034800, offset: 14400 }, { second: 1224972000, offset: 18000 }, { second: 1238274000, offset: 14400 }] }
}
