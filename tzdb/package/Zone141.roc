import DatabaseRecord
Zone141 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Antarctica/Davis", source_version: "2025b", source_digest: "3e89bfdbaeebb28665eb22ef62596efd25b5922c48ad23e6b1df872f3b67df76", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 0.I32, minimum_offset: 0.I32, maximum_offset: 25200.I32, transitions: [{ second: -409190400, offset: 25200 }, { second: -163062000, offset: 0 }, { second: -28857600, offset: 25200 }, { second: 1255806000, offset: 18000 }, { second: 1268251200, offset: 25200 }, { second: 1319742000, offset: 18000 }, { second: 1329854400, offset: 25200 }] }
}
