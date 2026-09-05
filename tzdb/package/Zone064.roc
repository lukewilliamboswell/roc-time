import DatabaseRecord
Zone064 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/El_Salvador", source_version: "2025b", source_digest: "e308ec0a9447f40164e5a6cb01b9eebfece8ba144a7306f469e9e4fa75ad9b3d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -21408.I32, minimum_offset: -21600.I32, maximum_offset: -18000.I32, transitions: [{ second: -1546279392, offset: -21600 }, { second: 547020000, offset: -18000 }, { second: 559717200, offset: -21600 }, { second: 578469600, offset: -18000 }, { second: 591166800, offset: -21600 }] }
}
