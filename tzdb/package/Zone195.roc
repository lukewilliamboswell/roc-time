import DatabaseRecord
Zone195 :: [].{
 get : Str -> DatabaseRecord.Value
 get = |requested| { schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: "Asia/Singapore", source_version: "2025b", source_digest: "0954b2d9a301d94f4348024606a71bbcb2fa24d3cd3709f5bc8bca605039785d", profile: "iana-2025b-wheel-2025.2-posix-1800-2200-v1", future_handling: "expanded-through-validity", start_second: -5364662400.I64, end_second: 7258118400.I64, initial_offset: 24925.I32, minimum_offset: 24925.I32, maximum_offset: 32400.I32, transitions: [{ second: -2177477725, offset: 24925 }, { second: -2038200925, offset: 25200 }, { second: -1167634800, offset: 26400 }, { second: -1073028000, offset: 26400 }, { second: -894180000, offset: 27000 }, { second: -879665400, offset: 32400 }, { second: -767005200, offset: 27000 }, { second: 378662400, offset: 28800 }] }
}
