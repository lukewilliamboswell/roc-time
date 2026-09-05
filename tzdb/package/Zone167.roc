import DatabaseRecord
Zone167 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Kolkata", source_version: "2025b", source_digest: "3a00bdbe1bc4959e727567c730ba51b03455ecd455f7c190c5ad14386eb79b0d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 21208.I32, minimum_offset: 19270.I32, maximum_offset: 23400.I32, transitions: [{ second: -3645237208, offset: 21200 }, { second: -3155694800, offset: 19270 }, { second: -2019705670, offset: 19800 }, { second: -891581400, offset: 23400 }, { second: -872058600, offset: 19800 }, { second: -862637400, offset: 23400 }, { second: -764145000, offset: 19800 }] }
}
