import DatabaseRecord
Zone135 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "America/Tegucigalpa", source_version: "2025b", source_digest: "2a5bea0491acc1af43217944dda714fa981de0816a0de051ad4cf4d8f9a5342d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: -20932.I32, minimum_offset: -21600.I32, maximum_offset: -18000.I32, transitions: [{ second: -1538503868, offset: -21600 }, { second: 547020000, offset: -18000 }, { second: 559717200, offset: -21600 }, { second: 578469600, offset: -18000 }, { second: 591166800, offset: -21600 }, { second: 1146981600, offset: -18000 }, { second: 1154926800, offset: -21600 }] }
}
